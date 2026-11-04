package com.ativalocacao.instalador

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

/**
 * Tela unica: um botao grande que muda conforme a situacao
 * (instalar / atualizar / abrir o Ativa Suporte).
 */
class MainActivity : Activity() {
    private val blue = Color.parseColor("#15559F")
    private val green = Color.parseColor("#48AE3E")
    private val main = Handler(Looper.getMainLooper())

    private lateinit var title: TextView
    private lateinit var message: TextView
    private lateinit var button: Button
    private lateinit var progress: ProgressBar
    private lateinit var footer: TextView

    private var release: Release? = null
    private var busy = false
    private var openWhenInstalled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildLayout())
        UpdateJobService.schedule(this)
    }

    override fun onResume() {
        super.onResume()
        Installer.listener = { success, text -> main.post { onInstallResult(success, text) } }
        if (!busy) refresh()
    }

    override fun onPause() {
        super.onPause()
        Installer.listener = null
    }

    // ------------------------------------------------------------- estados

    private fun refresh() {
        show("Procurando a versão mais nova…", "Só um instante.", null)
        Thread {
            try {
                val latest = Releases.latest()
                main.post {
                    release = latest
                    showState()
                }
            } catch (e: Exception) {
                main.post {
                    show(
                        "Sem conexão com a internet",
                        "Confira o Wi-Fi ou os dados móveis e tente de novo.\n(${e.message})",
                        "TENTAR DE NOVO" to blue,
                    ) { refresh() }
                }
            }
        }.start()
    }

    private fun showState() {
        val latest = release ?: return refresh()
        val installed = Releases.installedVersion(this)
        footer.text = "Instalada: ${installed ?: "nenhuma"} · disponível: ${latest.version}"
        when {
            installed == null -> show(
                "Vamos instalar o Ativa Suporte",
                "É o aplicativo de ajuda do T.I. da Ativa. Toque no botão verde.",
                "INSTALAR O ATIVA SUPORTE" to green,
            ) { startInstall() }
            Releases.isNewer(latest.version, installed) -> show(
                "Tem atualização",
                "Uma versão nova do Ativa Suporte está disponível.",
                "ATUALIZAR O ATIVA SUPORTE" to green,
            ) { startInstall() }
            else -> show(
                "Tudo certo!",
                "O Ativa Suporte está instalado e atualizado.\nEste app atualiza o Ativa Suporte sozinho.",
                "ABRIR O ATIVA SUPORTE" to blue,
            ) { openSupport() }
        }
    }

    private fun startInstall() {
        val latest = release ?: return refresh()
        // Android 8+: este app precisa da permissao "instalar apps desconhecidos".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            askInstallPermission()
            return
        }
        busy = true
        openWhenInstalled = true
        progress.visibility = View.VISIBLE
        progress.progress = 0
        show("Baixando o Ativa Suporte…", "0%", null)
        Thread {
            try {
                val apk = Releases.download(this, latest) { percent ->
                    main.post {
                        progress.progress = percent
                        message.text = "$percent%"
                    }
                }
                main.post { show("Instalando…", "Se o celular perguntar, toque em Instalar.", null) }
                Installer.install(this, apk, interactive = true)
            } catch (e: Exception) {
                main.post {
                    busy = false
                    progress.visibility = View.GONE
                    show("Não deu certo", e.message ?: "Erro ao baixar.", "TENTAR DE NOVO" to blue) { startInstall() }
                }
            }
        }.start()
    }

    private fun onInstallResult(success: Boolean, text: String) {
        busy = false
        progress.visibility = View.GONE
        if (success) {
            show("Pronto!", text, "ABRIR O ATIVA SUPORTE" to blue) { openSupport() }
            if (openWhenInstalled) {
                openWhenInstalled = false
                main.postDelayed({ openSupport() }, 800)
            }
        } else {
            show("Não deu certo", text, "TENTAR DE NOVO" to blue) { refresh() }
        }
    }

    private fun askInstallPermission() {
        AlertDialog.Builder(this)
            .setTitle("Uma permissão, só uma vez")
            .setMessage(
                "Para instalar o Ativa Suporte, o celular precisa deixar este app instalar aplicativos.\n\n" +
                    "Na próxima tela, ligue a chave \"Permitir desta fonte\" e volte para cá."
            )
            .setPositiveButton("CONTINUAR") { _, _ ->
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            }
            .setNegativeButton("AGORA NÃO", null)
            .show()
    }

    private fun openSupport() {
        val intent = packageManager.getLaunchIntentForPackage(Releases.SUPPORT_PACKAGE)
        if (intent != null) startActivity(intent) else refresh()
    }

    // ------------------------------------------------------------- tela

    private fun show(head: String, body: String, action: Pair<String, Int>?, onClick: (() -> Unit)? = null) {
        title.text = head
        message.text = body
        if (action == null) {
            button.visibility = View.GONE
        } else {
            button.visibility = View.VISIBLE
            button.text = action.first
            (button.background as GradientDrawable).setColor(action.second)
            button.setOnClickListener { onClick?.invoke() }
        }
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    private fun buildLayout(): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(48), dp(24), dp(32))
            setBackgroundColor(Color.parseColor("#F3F6FB"))
        }
        column.addView(ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
        }, LinearLayout.LayoutParams(dp(96), dp(96)))
        column.addView(TextView(this).apply {
            text = "Ativa Instalador"
            setTextColor(blue)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(32))
        })
        title = TextView(this).apply {
            setTextColor(Color.parseColor("#142A5B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 23f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        column.addView(title)
        message = TextView(this).apply {
            setTextColor(Color.parseColor("#55627C"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(24))
        }
        column.addView(message)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            visibility = View.GONE
        }
        column.addView(progress, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(16)).apply {
            bottomMargin = dp(24)
        })
        button = Button(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(green)
            }
            visibility = View.GONE
        }
        column.addView(button, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(80)))
        footer = TextView(this).apply {
            setTextColor(Color.parseColor("#8A94AA"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setPadding(0, dp(28), 0, 0)
        }
        column.addView(footer)
        return ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(Color.parseColor("#F3F6FB"))
            addView(column)
        }
    }
}
