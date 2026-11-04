package com.ativalocacao.instalador

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * A cada ~12 h, com internet: se houver Ativa Suporte novo, atualiza sozinho.
 * Sem perguntar so no Android 12+ (e por ter sido o Ativa Instalador quem
 * instalou); nos outros, a atualizacao fica para quando a pessoa abrir o app.
 * So atualiza - a primeira instalacao e sempre pelo botao.
 */
class UpdateJobService : JobService() {
    companion object {
        private const val JOB_ID = 4201
        private const val TAG = "AtivaInstalador"

        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            if (scheduler.getPendingJob(JOB_ID) != null) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, UpdateJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(12 * 60 * 60 * 1000L)
                .setPersisted(true)
                .build()
            scheduler.schedule(job)
        }
    }

    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            var retry = false
            try {
                val installed = Releases.installedVersion(this)
                if (installed != null) {
                    val release = Releases.latest()
                    if (Releases.isNewer(release.version, installed)) {
                        Log.i(TAG, "Atualizando Ativa Suporte $installed -> ${release.version}")
                        val apk = Releases.download(this, release) {}
                        Installer.install(this, apk, interactive = false)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Verificacao de atualizacao falhou: ${e.message}")
                retry = true
            }
            jobFinished(params, retry)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
