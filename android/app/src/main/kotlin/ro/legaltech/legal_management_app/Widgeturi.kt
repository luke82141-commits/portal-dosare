package ro.legaltech.legal_management_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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

    /** Un rând de termen: zi, oră, număr dosar, instanță; atingerea deschide dosarul. */
    fun rand(ctx: Context, v: RemoteViews, d: SharedPreferences, cheie: String, ids: IntArray) {
        val (idRand, idZi, idOra, idDosar, idInst) = ids
        val nr = s(d, "${cheie}_dosar")
        if (nr.isEmpty()) {
            v.setViewVisibility(idRand, View.GONE)
            return
        }
        v.setViewVisibility(idRand, View.VISIBLE)
        v.setTextViewText(idZi, s(d, "${cheie}_zi"))
        text(v, idOra, s(d, "${cheie}_ora"))
        v.setTextViewText(idDosar, nr)
        v.setTextViewText(idInst, s(d, "${cheie}_inst"))
        v.setOnClickPendingIntent(idRand, dosar(ctx, s(d, "${cheie}_cheie")))
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
                W.text(this, R.id.mic_act, W.s(d, "act_text"))
                setOnClickPendingIntent(R.id.mic_act, W.deschide(ctx, "actualizari"))
            }
            mgr.updateAppWidget(id, v)
        }
    }
}

class WidgetMediu : HomeWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        val randuri = arrayOf(
            intArrayOf(R.id.m0, R.id.m0_zi, R.id.m0_ora, R.id.m0_dosar, R.id.m0_inst),
            intArrayOf(R.id.m1, R.id.m1_zi, R.id.m1_ora, R.id.m1_dosar, R.id.m1_inst),
            intArrayOf(R.id.m2, R.id.m2_zi, R.id.m2_ora, R.id.m2_dosar, R.id.m2_inst),
        )
        for (id in ids) {
            val v = if (!W.pro(d)) W.blocat(ctx) else RemoteViews(ctx.packageName, R.layout.widget_mediu).apply {
                setOnClickPendingIntent(R.id.radacina, W.deschide(ctx, "termene"))
                randuri.forEachIndexed { i, r -> W.rand(ctx, this, d, "t$i", r) }
                setViewVisibility(R.id.m_gol, if (W.s(d, "t0_dosar").isEmpty()) View.VISIBLE else View.GONE)
                W.text(this, R.id.m_act, W.s(d, "act_text"))
                setOnClickPendingIntent(R.id.m_act, W.deschide(ctx, "actualizari"))
            }
            mgr.updateAppWidget(id, v)
        }
    }
}

class WidgetMare : HomeWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        val randuri = arrayOf(
            intArrayOf(R.id.g0, R.id.g0_zi, R.id.g0_ora, R.id.g0_dosar, R.id.g0_inst),
            intArrayOf(R.id.g1, R.id.g1_zi, R.id.g1_ora, R.id.g1_dosar, R.id.g1_inst),
            intArrayOf(R.id.g2, R.id.g2_zi, R.id.g2_ora, R.id.g2_dosar, R.id.g2_inst),
            intArrayOf(R.id.g3, R.id.g3_zi, R.id.g3_ora, R.id.g3_dosar, R.id.g3_inst),
            intArrayOf(R.id.g4, R.id.g4_zi, R.id.g4_ora, R.id.g4_dosar, R.id.g4_inst),
            intArrayOf(R.id.g5, R.id.g5_zi, R.id.g5_ora, R.id.g5_dosar, R.id.g5_inst),
        )
        val actualizari = arrayOf(
            intArrayOf(R.id.ga0, R.id.ga0_dosar, R.id.ga0_text),
            intArrayOf(R.id.ga1, R.id.ga1_dosar, R.id.ga1_text),
        )
        for (id in ids) {
            val v = if (!W.pro(d)) W.blocat(ctx) else RemoteViews(ctx.packageName, R.layout.widget_mare).apply {
                setOnClickPendingIntent(R.id.radacina, W.deschide(ctx, "termene"))
                randuri.forEachIndexed { i, r -> W.rand(ctx, this, d, "s$i", r) }
                setViewVisibility(R.id.g_gol, if (W.s(d, "s0_dosar").isEmpty()) View.VISIBLE else View.GONE)
                W.text(this, R.id.g_mai_multe, W.s(d, "s_mai_multe"))
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
    }
}
