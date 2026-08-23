import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/auth/application/auth_providers.dart';
import 'package:nasz_budzet_domowy/features/auth/data/auth_repository.dart';
import 'package:nasz_budzet_domowy/features/auth/presentation/forgot_password_screen.dart';
import 'package:nasz_budzet_domowy/features/onboarding/application/intro_providers.dart';
import 'package:nasz_budzet_domowy/features/onboarding/presentation/intro_carousel.dart';
import 'package:nasz_budzet_domowy/shared/widgets/inline_error.dart';
import 'package:nasz_budzet_domowy/shared/widgets/loading_filled_button.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Ekran logowania / rejestracji email+hasło. Toggle Login ↔ Sign-up,
/// po sukcesie router automatycznie przerzuca na onboarding lub home.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Mode { signIn, signUp }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _showPassword = false;
  bool _submitting = false;
  String? _errorMessage;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final repo = ref.read(authRepositoryProvider);
    final result = _mode == _Mode.signIn
        ? await repo.signInWithPassword(email: email, password: password)
        : await repo.signUp(email: email, password: password);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorMessage = _resultToMessage(result);
    });
    // Sukces → router (via onAuthStateChange) przerzuci na onboarding/home.
  }

  String? _resultToMessage(AuthResult r) {
    return switch (r) {
      AuthSuccess() => null,
      AuthInvalidCredentials() =>
        'Email lub hasło niepoprawne. Sprawdź dane i spróbuj ponownie.',
      AuthEmailAlreadyExists() =>
        'Konto z tym emailem już istnieje. Wybierz "Zaloguj się".',
      AuthWeakPassword() => 'Hasło musi mieć co najmniej 6 znaków.',
      AuthInvalidOtp() => 'Kod resetu jest niepoprawny lub wygasł.',
      AuthGenericFailure(:final message) => 'Nie udało się: $message',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Przy pierwszym uruchomieniu (przed logowaniem) pokazujemy intro
    // carousel zamiast formularza. Po obejrzeniu → markIntroSeen → formularz.
    final introSeen = ref.watch(introSeenProvider);
    if (introSeen.value == false) {
      return IntroCarousel(
        onFinish: () => markIntroSeen(ref),
      );
    }

    final theme = Theme.of(context);
    final isSignIn = _mode == _Mode.signIn;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Nasz budżet domowy',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isSignIn
                      ? 'Zaloguj się — email i hasło.'
                      : 'Załóż konto — email i hasło (min. 6 znaków).',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(
                      value: _Mode.signIn,
                      label: Text('Zaloguj się'),
                      icon: AppIcon(Icons.login),
                    ),
                    ButtonSegment(
                      value: _Mode.signUp,
                      label: Text('Załóż konto'),
                      icon: AppIcon(Icons.person_add_alt),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _submitting
                      ? null
                      : (s) => setState(() {
                            _mode = s.first;
                            _errorMessage = null;
                          }),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'adrian@example.com',
                    prefixIcon: AppIcon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Wpisz email.';
                    if (!_emailRegex.hasMatch(v)) {
                      return 'Email wygląda na niepoprawny.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Hasło',
                    prefixIcon: const AppIcon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Ukryj hasło' : 'Pokaż hasło',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) {
                    final v = value ?? '';
                    if (v.isEmpty) return 'Wpisz hasło.';
                    if (!isSignIn && v.length < 6) {
                      return 'Hasło musi mieć co najmniej 6 znaków.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  InlineError(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],
                LoadingFilledButton(
                  label: isSignIn ? 'Zaloguj się' : 'Załóż konto',
                  isLoading: _submitting,
                  icon: isSignIn ? Icons.login : Icons.person_add_alt,
                  onPressed: _submit,
                ),
                if (isSignIn)
                  Center(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialEmail: _emailController.text.trim(),
                                  ),
                                ),
                              ),
                      child: const Text('Nie pamiętam hasła'),
                    ),
                  ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    isSignIn
                        ? 'Nie masz konta? Kliknij "Załóż konto" powyżej.'
                        : 'Masz już konto? Kliknij "Zaloguj się" powyżej.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
