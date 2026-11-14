package ro.legaltech.legal_management_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widgeturile de pe ecranul principal. Datele le scrie aplicația
 * (lib/services/widget_service.dart) după fiecare verificare; aici doar le
 * așezăm în layout. Fără Pro, widgetul arată mesajul de deblocare.
 */
private object W {
    fun s(d: SharedPreferences, k: String): String = d.getString(k, "") ?: ""

    fun deschide(ctx: Context, cale: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(ctx, MainActivity::class.java, Uri.parse("portaldosare://$cale"))

    fun dosar(ctx: Context, cheie: String): PendingIntent =
        deschide(ctx, "dosar?cheie=" + Uri.encode(cheie))

    fun text(v: RemoteViews, id: Int, t: String) {
        v.setTextViewText(id, t)
        v.setViewVisibility(id, if (t.isEmpty()) View.GONE else View.VISIBLE)
    }

    fun blocat(ctx: Context): RemoteViews =
        RemoteViews(ctx.packageName, R.layout.widget_blocat).apply {
            setOnClickPendingIntent(R.id.radacina, deschide(ctx, "widgeturi"))
        }

    fun pro(d: SharedPreferences) = s(d, "pro") == "1"

    /**
     * Leagă lista derulabilă [idLista] de termenele cu prefixul [lista]
     * („t” = următoarele, „s” = cele din 7 zile). Atingerea unui rând deschide
     * dosarul: șablonul e aici, fiecare rând își pune adresa (fill-in).
     */
    fun lista(ctx: Context, v: RemoteViews, widgetId: Int, idLista: Int, idGol: Int, lista: String) {
        val adaptor = Intent(ctx, TermeneWidgetService::class.java).apply {
            putExtra(TermeneWidgetService.LISTA, lista)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            // Adresă unică pe widget, altfel Android refolosește aceeași fabrică.
            data = Uri.parse("portaldosare-lista://$lista/$widgetId")
        }
        @Suppress("DEPRECATION")
        v.setRemoteAdapter(idLista, adaptor)
        v.setEmptyView(idLista, idGol)
        val sablon = Intent(ctx, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        v.setPendingIntentTemplate(idLista, PendingIntent.getActivity(ctx, widgetId, sablon, flags))
    }
}

/** Furnizează rândurile listelor din widgeturi, din datele scrise de aplicație. */
class TermeneWidgetService : RemoteViewsService() {
    companion object {
        const val LISTA = "lista"
    }

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Fabrica(applicationContext, intent.getStringExtra(LISTA) ?: "t")

    private class Fabrica(val ctx: Context, val p: String) : RemoteViewsFactory {
        private var n = 0
        private lateinit var d: SharedPreferences

        override fun onCreate() {}
        override fun onDestroy() {}

        override fun onDataSetChanged() {
            d = HomeWidgetPlugin.getData(ctx)
            n = (W.s(d, "${p}_n").toIntOrNull() ?: 0).coerceIn(0, 30)
            // „s_n” poate număra mai multe termene decât am trimis.
            while (n > 0 && W.s(d, "${p}${n - 1}_dosar").isEmpty()) n--
        }

        override fun getCount() = n

        override fun getViewAt(i: Int): RemoteViews {
            val k = "$p$i"
            return RemoteViews(ctx.packageName, R.layout.widget_rand).apply {
                setTextViewText(R.id.r_zi, W.s(d, "${k}_zi"))
                W.text(this, R.id.r_ora, W.s(d, "${k}_ora"))
                setTextViewText(R.id.r_dosar, W.s(d, "${k}_dosar"))
                setTextViewText(R.id.r_inst, W.s(d, "${k}_inst"))
                val adresa = "portaldosare://dosar?cheie=" + Uri.encode(W.s(d, "${k}_cheie"))
                setOnClickFillInIntent(R.id.r_rand, Intent().setData(Uri.parse(adresa)))
            }
        }

        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(i: Int) = i.toLong()
        override fun hasStableIds() = false
    }
}

class WidgetMic : HomeWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = if (!W.pro(d)) W.blocat(ctx) else RemoteViews(ctx.packageName, R.layout.widget_mic).apply {
                val nr = W.s(d, "t0_dosar")
                if (nr.isEmpty()) {
                    setTextViewText(R.id.mic_cand, "—")
                    W.text(this, R.id.mic_dosar, "")
                    W.text(this, R.id.mic_inst, "Niciun termen viitor")
                    setOnClickPendingIntent(R.id.radacina, W.deschide(ctx, "termene"))
                } else {
                    val ora = W.s(d, "t0_ora")
                    setTextViewText(R.id.mic_cand, W.s(d, "t0_zi") + if (ora.isEmpty()) "" else " · $ora")
                    W.text(this, R.id.mic_dosar, nr)
                    W.text(this, R.id.mic_inst, W.s(d, "t0_inst"))
                    setOnClickPendingIntent(R.id.radacina, W.dosar(ctx, W.s(d, "t0_cheie")))
                }
                W.text(this, R.id.mic_mai, W.s(d, "mic_mai"))
                W.text(this, R.id.mic_act, W.s(d, "act_text"))
                setOnClickPendingIntent(R.id.mic_act, W.deschide(ctx, "actualizari"))
            }
            mgr.updateAppWidget(id, v)
        }
    }
}

class WidgetMediu : HomeWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = if (!W.pro(d)) W.blocat(ctx) else RemoteViews(ctx.packageName, R.layout.widget_mediu).apply {
                setOnClickPendingIntent(R.id.radacina, W.deschide(ctx, "termene"))
                W.lista(ctx, this, id, R.id.m_lista, R.id.m_gol, "t")
                W.text(this, R.id.m_act, W.s(d, "act_text"))
                setOnClickPendingIntent(R.id.m_act, W.deschide(ctx, "actualizari"))
            }
            mgr.updateAppWidget(id, v)
        }
        @Suppress("DEPRECATION")
        mgr.notifyAppWidgetViewDataChanged(ids, R.id.m_lista)
    }
}

class WidgetMare : HomeWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        val actualizari = arrayOf(
            intArrayOf(R.id.ga0, R.id.ga0_dosar, R.id.ga0_text),
            intArrayOf(R.id.ga1, R.id.ga1_dosar, R.id.ga1_text),
        )
        for (id in ids) {
            val v = if (!W.pro(d)) W.blocat(ctx) else RemoteViews(ctx.packageName, R.layout.widget_mare).apply {
                setOnClickPendingIntent(R.id.radacina, W.deschide(ctx, "termene"))
                W.lista(ctx, this, id, R.id.g_lista, R.id.g_gol, "s")
                W.text(this, R.id.g_act, W.s(d, "act_text"))
                setOnClickPendingIntent(R.id.g_act, W.deschide(ctx, "actualizari"))

                var cuActualizari = false
                actualizari.forEachIndexed { i, (idRand, idDosar, idText) ->
                    val nr = W.s(d, "a${i}_dosar")
                    if (nr.isEmpty()) {
                        setViewVisibility(idRand, View.GONE)
                    } else {
                        cuActualizari = true
                        setViewVisibility(idRand, View.VISIBLE)
                        setTextViewText(idDosar, nr)
                        setTextViewText(idText, W.s(d, "a${i}_text"))
                        setOnClickPendingIntent(idRand, W.dosar(ctx, W.s(d, "a${i}_cheie")))
                    }
                }
                setViewVisibility(R.id.g_act_titlu, if (cuActualizari) View.VISIBLE else View.GONE)
                W.text(this, R.id.g_actualizat, W.s(d, "actualizat"))
            }
            mgr.updateAppWidget(id, v)
        }
        @Suppress("DEPRECATION")
        mgr.notifyAppWidgetViewDataChanged(ids, R.id.g_lista)
    }
}
