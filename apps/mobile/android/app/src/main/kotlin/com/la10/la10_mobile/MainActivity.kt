package com.la10.la10_mobile

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/// Activity raíz de la app. Habilitamos flags `showWhenLocked` y
/// `turnScreenOn` cuando se lanza por un full-screen intent (notificación
/// estilo "llamada entrante" para una oferta nueva). Sin estos flags el
/// fullScreenIntent solo muestra heads-up, no popup en lock screen.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }
}
