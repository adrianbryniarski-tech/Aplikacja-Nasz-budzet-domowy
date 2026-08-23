import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Limit czasu pojedynczego zapisu do Supabase. Bez niego zawieszony
/// socket (hotelowe Wi-Fi, uśpiony projekt Supabase) trzyma przycisk
/// „Zapisz" w kręcącym się stanie bez końca, bez możliwości wyjścia.
const kSupabaseWriteTimeout = Duration(seconds: 15);

/// Tłumaczy wyjątek techniczny na krótki komunikat po polsku — to czyta
/// rodzina, nie programista. Surowe `PostgrestException(message: …,
/// code: 42501, hint: null)` nikomu nic nie mówi.
String humanizeError(Object error) {
  if (error is TimeoutException) {
    return 'Serwer nie odpowiada. Spróbuj ponownie za chwilę.';
  }
  if (error is SocketException || error is http.ClientException) {
    return 'Brak połączenia z internetem. Sprawdź zasięg lub Wi-Fi.';
  }
  if (error is AuthException) {
    return 'Problem z sesją — wyloguj się i zaloguj ponownie.';
  }
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'Brak dostępu do tych danych — sprawdź, czy jesteś '
          'w gospodarstwie.';
    }
    return 'Serwer ma chwilowy problem. Spróbuj ponownie za moment.';
  }
  return 'Coś poszło nie tak. Spróbuj ponownie.';
}
