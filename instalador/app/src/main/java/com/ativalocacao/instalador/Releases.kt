package com.ativalocacao.instalador

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Versao do Ativa Suporte publicada no GitHub (Releases). */
data class Release(val version: String, val apkUrl: String, val apkName: String, val size: Long, val sha256: String?)

object Releases {
    const val SUPPORT_PACKAGE = "com.ativalocacao.suporte"
    private const val API = "https://api.github.com/repos/diego-o-pessoa/ativa-suporte-android/releases?per_page=15"

    /** APK certo para este celular: 64 bits (quase todos) ou 32 bits (antigos). */
    private fun apkSuffix(): String =
        if (Build.SUPPORTED_ABIS.any { it == "arm64-v8a" }) "-arm64.apk" else "-armv7.apk"

    /** Versao mais nova do Ativa Suporte (tags "v1.0.N"; ignora as do instalador). */
    fun latest(): Release {
        val connection = (URL(API).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 20_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "AtivaInstalador")
        }
        try {
            if (connection.responseCode != 200) {
                throw IOException("GitHub respondeu ${connection.responseCode}")
            }
            val releases = JSONArray(connection.inputStream.bufferedReader().use { it.readText() })
            val suffix = apkSuffix()
            for (i in 0 until releases.length()) {
                val release = releases.getJSONObject(i)
                val tag = release.optString("tag_name")
                if (release.optBoolean("draft") || release.optBoolean("prerelease") || !Regex("""^v\d+\.\d+\.\d+$""").matches(tag)) {
                    continue
                }
                val assets = release.optJSONArray("assets") ?: continue
                for (j in 0 until assets.length()) {
                    val asset = assets.getJSONObject(j)
                    val name = asset.optString("name")
                    if (name.startsWith("ativa-suporte-") && name.endsWith(suffix) && !name.contains("TESTE")) {
                        val digest = asset.optString("digest").removePrefix("sha256:").lowercase()
                        return Release(
                            version = tag.removePrefix("v"),
                            apkUrl = asset.getString("browser_download_url"),
                            apkName = name,
                            size = asset.optLong("size"),
                            sha256 = digest.takeIf { it.length == 64 },
                        )
                    }
                }
            }
            throw IOException("Nenhuma versão do Ativa Suporte publicada ainda.")
        } finally {
            connection.disconnect()
        }
    }

    /** Versao instalada do Ativa Suporte ("1.0.12"), ou null se nao instalado. */
    fun installedVersion(context: Context): String? = try {
        context.packageManager.getPackageInfo(SUPPORT_PACKAGE, 0).versionName
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /** true se [available] for mais nova que [installed] ("1.0.10" > "1.0.9"). */
    fun isNewer(available: String, installed: String?): Boolean {
        if (installed == null) return true
        val a = available.split('.').map { it.toIntOrNull() ?: 0 }
        val b = installed.split('.').map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }

    /** Baixa o APK (com progresso 0..100) e confere o SHA-256 publicado. */
    fun download(context: Context, release: Release, progress: (Int) -> Unit): File {
        val target = File(context.cacheDir, "ativa-suporte.apk")
        var url = URL(release.apkUrl)
        var connection: HttpURLConnection
        // GitHub redireciona para outro endereco: segue ate 5 vezes.
        var redirects = 0
        while (true) {
            connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 20_000
                readTimeout = 60_000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "AtivaInstalador")
            }
            val code = connection.responseCode
            if (code in 300..399 && redirects < 5) {
                url = URL(url, connection.getHeaderField("Location"))
                connection.disconnect()
                redirects++
                continue
            }
            if (code != 200) throw IOException("Download respondeu $code")
            break
        }
        val total = connection.contentLengthLong.takeIf { it > 0 } ?: release.size
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    var last = -1
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                        done += read
                        if (total > 0) {
                            val percent = (done * 100 / total).toInt()
                            if (percent != last) {
                                last = percent
                                progress(percent)
                            }
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (release.sha256 != null && actual != release.sha256) {
            target.delete()
            throw IOException("O arquivo baixado veio corrompido. Tente de novo.")
        }
        return target
    }
}
