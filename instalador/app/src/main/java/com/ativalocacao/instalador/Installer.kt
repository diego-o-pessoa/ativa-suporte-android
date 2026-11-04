package com.ativalocacao.instalador

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File

/**
 * Instala pelo PackageInstaller (o mesmo caminho das lojas de aplicativos), e
 * nao abrindo o APK como arquivo. Assim:
 *  - o Ativa Instalador fica sendo "quem instalou" o Ativa Suporte e pode
 *    atualiza-lo depois sem perguntar (Android 12+);
 *  - o app e marcado como vindo de uma loja (Android 13+), o que evita a
 *    "Configuracao restrita" da Acessibilidade em varios aparelhos.
 */
object Installer {
    const val ACTION_RESULT = "com.ativalocacao.instalador.INSTALL_RESULT"

    /** Quem esta na tela quer saber o resultado (null = ninguem). */
    @Volatile
    var listener: ((success: Boolean, message: String) -> Unit)? = null

    fun install(context: Context, apk: File, interactive: Boolean) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(Releases.SUPPORT_PACKAGE)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                setPackageSource(PackageInstaller.PACKAGE_SOURCE_STORE)
            }
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("ativa-suporte.apk", 0, apk.length()).use { output ->
                    input.copyTo(output, 64 * 1024)
                    session.fsync(output)
                }
            }
            val intent = Intent(context, InstallResultReceiver::class.java)
                .setAction(ACTION_RESULT)
                .putExtra(InstallResultReceiver.EXTRA_INTERACTIVE, interactive)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pending.intentSender)
        }
    }
}

class InstallResultReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_INTERACTIVE = "interactive"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val interactive = intent.getBooleanExtra(EXTRA_INTERACTIVE, false)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // O Android quer a confirmacao da pessoa ("Instalar"/"Atualizar").
                // Em segundo plano (atualizacao automatica) nao interrompe: tenta
                // de novo quando o Ativa Instalador for aberto.
                if (interactive) {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(confirm)
                    }
                } else {
                    Installer.listener?.invoke(false, "Atualização pronta: abra o Ativa Instalador para concluir.")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Installer.listener?.invoke(true, "Ativa Suporte instalado!")
            PackageInstaller.STATUS_FAILURE_ABORTED -> Installer.listener?.invoke(false, "Instalação cancelada. Toque no botão para tentar de novo.")
            PackageInstaller.STATUS_FAILURE_BLOCKED -> Installer.listener?.invoke(false, blockedMessage(intent))
            PackageInstaller.STATUS_FAILURE_CONFLICT -> Installer.listener?.invoke(
                false,
                "Já existe um Ativa Suporte de teste neste celular. Desinstale o Ativa Suporte e toque no botão de novo."
            )
            PackageInstaller.STATUS_FAILURE_STORAGE -> Installer.listener?.invoke(false, "Sem espaço no celular. Libere espaço e tente de novo.")
            else -> Installer.listener?.invoke(false, "Não foi possível instalar: " + (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "erro $status"))
        }
    }

    private fun blockedMessage(intent: Intent): String {
        val detail = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE).orEmpty()
        return "O Android bloqueou a instalação (Play Protect ou verificação de desenvolvedor). " +
            "Siga o guia do T.I. para liberar e toque no botão de novo." + if (detail.isNotBlank()) "\n($detail)" else ""
    }
}
