package pl.naszbudzetdomowy.nasz_budzet_domowy

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (nie FlutterActivity) — wymagane przez local_auth
// (systemowy dialog biometrii działa na FragmentActivity).
class MainActivity : FlutterFragmentActivity()
