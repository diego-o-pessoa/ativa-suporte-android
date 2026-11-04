// Ativa Instalador: instala e atualiza o Ativa Suporte a partir das versoes
// publicadas no GitHub (Releases). Sem bibliotecas externas: so o Android.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Mesma chave do Ativa Suporte (segredos do GitHub, gravados pelo workflow).
val keystoreFile = System.getenv("ATIVA_KEYSTORE_FILE")

android {
    namespace = "com.ativalocacao.instalador"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.ativalocacao.instalador"
        minSdk = 24
        targetSdk = 34
        versionCode = (System.getenv("ATIVA_VERSION_CODE") ?: "1").toInt()
        versionName = System.getenv("ATIVA_VERSION_NAME") ?: "1.0.0"
    }

    signingConfigs {
        if (keystoreFile != null) {
            create("ativa") {
                storeFile = file(keystoreFile)
                storePassword = System.getenv("ATIVA_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ATIVA_KEY_ALIAS")
                keyPassword = System.getenv("ATIVA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystoreFile != null) signingConfigs.getByName("ativa") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}
