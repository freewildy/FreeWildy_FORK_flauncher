/*
 * FLauncher Locked - GPL-3.0-or-later
 */

import 'package:flauncher/providers/lock_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<bool> requestLauncherUnlock(BuildContext context) async {
  final lockService = context.read<LockService>();
  if (lockService.isAdministratorUnlocked) return true;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(createPassword: !lockService.hasPassword),
  );
  return result == true;
}

class _PasswordDialog extends StatefulWidget {
  final bool createPassword;

  const _PasswordDialog({required this.createPassword});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _recoveryControllers =
      List<TextEditingController>.generate(4, (_) => TextEditingController());
  final _creationFocusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
  int _creationStep = 0;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    for (final controller in _recoveryControllers) {
      controller.dispose();
    }
    for (final focusNode in _creationFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.createPassword
            ? 'Protéger les paramètres du lanceur'
            : 'Paramètres verrouillés'),
        content: SizedBox(
          width: 460,
          height: widget.createPassword ? 180 : 145,
          child: widget.createPassword
              ? _creationStepContent(context)
              : _unlockContent(),
        ),
        actions: widget.createPassword ? _creationActions() : _unlockActions(),
      );

  Widget _unlockContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Saisissez le mot de passe du lanceur pour continuer.'),
          SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _unlock(),
            decoration:
                InputDecoration(labelText: 'Mot de passe', errorText: _error),
          ),
        ],
      );

  Widget _creationStepContent(BuildContext context) {
    final controller = _creationController(_creationStep);
    final questionIndex = _creationStep - 2;
    final isSecretQuestion = questionIndex >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Étape ${_creationStep + 1} sur 6',
                style: Theme.of(context).textTheme.caption),
            Spacer(),
            if (_creationStep > 0)
              TextButton(
                  onPressed: _busy ? null : _previousCreation,
                  child: Text('Précédent')),
            TextButton(
              onPressed: _busy ? null : _advanceCreation,
              child: Text(_creationStep == 5 ? 'Créer' : 'Suivant'),
            ),
          ],
        ),
        Text(_creationPrompt(_creationStep), maxLines: 2),
        SizedBox(height: 4),
        TextField(
          key: ValueKey<int>(_creationStep),
          controller: controller,
          focusNode: _creationFocusNodes[_creationStep],
          autofocus: true,
          obscureText: _creationStep < 2,
          keyboardType:
              _creationStep == 2 ? TextInputType.datetime : TextInputType.text,
          textInputAction:
              _creationStep == 5 ? TextInputAction.done : TextInputAction.next,
          onEditingComplete: () {
            if (_creationStep == 4)
              _correctKnownCarMake(_recoveryControllers[2]);
            _advanceCreation();
          },
          decoration: InputDecoration(
            labelText: isSecretQuestion
                ? 'Réponse'
                : (_creationStep == 0 ? 'Mot de passe' : 'Confirmation'),
            helperText:
                _creationStep == 4 ? 'Ex. : Citroën C3, Renault Clio…' : null,
            errorText: _error,
          ),
        ),
      ],
    );
  }

  List<Widget> _creationActions() => [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text('Annuler')),
        if (_creationStep > 0)
          TextButton(
              onPressed: _busy ? null : _previousCreation,
              child: Text('Précédent')),
        TextButton(
          onPressed: _busy ? null : _advanceCreation,
          child: Text(_creationStep == 5 ? 'Créer' : 'Suivant'),
        ),
      ];

  List<Widget> _unlockActions() => [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text('Annuler')),
        if (context.watch<LockService>().canUseRecovery)
          TextButton(
              onPressed: _busy ? null : _openRecovery,
              child: Text('Mot de passe oublié ?')),
        TextButton(
            onPressed: _busy ? null : _unlock, child: Text('Déverrouiller')),
      ];

  TextEditingController _creationController(int step) {
    if (step == 0) return _passwordController;
    if (step == 1) return _confirmationController;
    return _recoveryControllers[step - 2];
  }

  String _creationPrompt(int step) {
    if (step == 0) return 'Choisissez un mot de passe d’au moins 4 caractères.';
    if (step == 1) return 'Saisissez à nouveau le mot de passe.';
    return _recoveryQuestions[step - 2];
  }

  void _previousCreation() => _goToCreationStep(_creationStep - 1);

  void _goToCreationStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _creationStep = step;
      _error = null;
    });
    WidgetsBinding.instance!.addPostFrameCallback((_) {
      if (mounted) _creationFocusNodes[_creationStep].requestFocus();
    });
  }

  Future<void> _advanceCreation() async {
    final value = _creationController(_creationStep).text.trim();
    if (_creationStep == 0 && value.length < 4) {
      setState(() => _error = 'Utilisez au moins 4 caractères.');
      return;
    }
    if (_creationStep == 1 &&
        _passwordController.text != _confirmationController.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    if (_creationStep >= 2 && value.isEmpty) {
      setState(() => _error = 'Saisissez une réponse.');
      return;
    }
    if (_creationStep == 4) _correctKnownCarMake(_recoveryControllers[2]);
    if (_creationStep < 5) {
      _goToCreationStep(_creationStep + 1);
      return;
    }

    final lockService = context.read<LockService>();
    setState(() => _busy = true);
    await lockService.setPassword(
      _passwordController.text,
      recoveryAnswers:
          _recoveryControllers.map((controller) => controller.text).toList(),
    );
    lockService.unlockAdministrator();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _unlock() async {
    final lockService = context.read<LockService>();
    if (lockService.verify(_passwordController.text)) {
      lockService.unlockAdministrator();
      Navigator.pop(context, true);
    } else {
      _passwordController.clear();
      setState(() => _error = 'Mot de passe incorrect.');
    }
  }

  Future<void> _openRecovery() async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RecoveryDialog());
    if (mounted && context.read<LockService>().isAdministratorUnlocked)
      Navigator.pop(context, true);
  }
}

const _recoveryQuestions = <String>[
  'Quelle est votre date de naissance ?',
  'Dans quelle ville êtes-vous né(e) ?',
  'Quels étaient le fabricant et le modèle de votre première voiture ?',
  'Quel est le nom de jeune fille de votre grand-mère maternelle ?',
];

class _RecoveryDialog extends StatefulWidget {
  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  final _answers =
      List<TextEditingController>.generate(4, (_) => TextEditingController());
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _focusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
  bool _answersVerified = false;
  int _step = 0;
  String? _error;

  @override
  void dispose() {
    for (final controller in _answers) {
      controller.dispose();
    }
    _password.dispose();
    _confirmation.dispose();
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_answersVerified
            ? 'Choisir un nouveau mot de passe'
            : 'Récupération du mot de passe'),
        content: SizedBox(
          width: 460,
          height: 180,
          child: _stepContent(context),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Annuler')),
          if (_step > 0)
            TextButton(onPressed: _previous, child: Text('Précédent')),
          TextButton(onPressed: _continue, child: Text(_actionLabel)),
        ],
      );

  Widget _stepContent(BuildContext context) {
    final controller = _currentController;
    final focusIndex = _answersVerified ? 4 + _step : _step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _answersVerified
                    ? 'Étape ${_step + 1} sur 2'
                    : 'Question ${_step + 1} sur 4 — 3 bonnes réponses suffisent',
                style: Theme.of(context).textTheme.caption,
              ),
            ),
            if (_step > 0)
              TextButton(onPressed: _previous, child: Text('Précédent')),
            TextButton(onPressed: _continue, child: Text(_actionLabel)),
          ],
        ),
        Text(_prompt, maxLines: 2),
        SizedBox(height: 4),
        TextField(
          key: ValueKey<String>(
              '${_answersVerified ? 'password' : 'answer'}-$_step'),
          controller: controller,
          focusNode: _focusNodes[focusIndex],
          autofocus: true,
          obscureText: _answersVerified,
          keyboardType: !_answersVerified && _step == 0
              ? TextInputType.datetime
              : TextInputType.text,
          textInputAction:
              _isLastStep ? TextInputAction.done : TextInputAction.next,
          onEditingComplete: _continue,
          decoration: InputDecoration(
            labelText: _answersVerified
                ? (_step == 0 ? 'Nouveau mot de passe' : 'Confirmation')
                : 'Réponse',
            helperText: !_answersVerified && _step == 2
                ? 'Ex. : Citroën C3, Renault Clio…'
                : null,
            errorText: _error,
          ),
        ),
      ],
    );
  }

  TextEditingController get _currentController {
    if (!_answersVerified) return _answers[_step];
    return _step == 0 ? _password : _confirmation;
  }

  String get _prompt {
    if (!_answersVerified) return _recoveryQuestions[_step];
    return _step == 0
        ? 'Choisissez un mot de passe d’au moins 4 caractères.'
        : 'Saisissez-le à nouveau.';
  }

  bool get _isLastStep => _answersVerified ? _step == 1 : _step == 3;

  String get _actionLabel {
    if (!_isLastStep) return 'Suivant';
    return _answersVerified ? 'Réinitialiser' : 'Vérifier';
  }

  void _previous() => _goToStep(_step - 1);

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    WidgetsBinding.instance!.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusIndex = _answersVerified ? 4 + _step : _step;
      _focusNodes[focusIndex].requestFocus();
    });
  }

  Future<void> _continue() async {
    final service = context.read<LockService>();
    if (!_answersVerified) {
      if (_step == 2) _correctKnownCarMake(_answers[2]);
      if (_step < 3) {
        _goToStep(_step + 1);
        return;
      }
      if (service.verifyRecoveryAnswers(
          _answers.map((controller) => controller.text).toList())) {
        setState(() {
          _answersVerified = true;
          _step = 0;
          _error = null;
        });
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          if (mounted) _focusNodes[4].requestFocus();
        });
      } else {
        setState(() {
          _step = 0;
          _error = 'Au moins 3 réponses doivent être correctes.';
        });
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          if (mounted) _focusNodes[0].requestFocus();
        });
      }
      return;
    }
    if (_step == 0 && _password.text.length < 4) {
      setState(() => _error = 'Utilisez au moins 4 caractères.');
    } else if (_step == 0) {
      _goToStep(1);
    } else if (_password.text != _confirmation.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
    } else {
      await service.resetPassword(_password.text);
      if (mounted) Navigator.pop(context);
    }
  }
}

Widget _recoveryField(int index, TextEditingController controller) => TextField(
      controller: controller,
      keyboardType: index == 0 ? TextInputType.datetime : TextInputType.text,
      onEditingComplete: () {
        if (index == 2) _correctKnownCarMake(controller);
      },
      decoration: InputDecoration(
        labelText: _recoveryQuestions[index],
        helperText: index == 2
            ? 'Exemples : Citroën, Renault, Peugeot, Volkswagen…'
            : null,
      ),
    );

void _correctKnownCarMake(TextEditingController controller) {
  final input = controller.text.trim();
  if (input.isEmpty) return;
  final separator = input.toLowerCase().startsWith('mercedes-benz')
      ? input.indexOf(' ', 'mercedes-benz'.length)
      : input.indexOf(RegExp(r'[\s-]'));
  final enteredMake =
      (separator < 0 ? input : input.substring(0, separator)).toLowerCase();
  final remainder = separator < 0 ? '' : input.substring(separator);
  const makes = <String, String>{
    'citroen': 'Citroën',
    'citroën': 'Citroën',
    'renault': 'Renault',
    'peugeot': 'Peugeot',
    'volkswagen': 'Volkswagen',
    'vw': 'Volkswagen',
    'mercedes': 'Mercedes-Benz',
    'mercedes-benz': 'Mercedes-Benz',
    'bmw': 'BMW',
    'audi': 'Audi',
    'ford': 'Ford',
    'fiat': 'Fiat',
    'toyota': 'Toyota',
    'honda': 'Honda',
    'nissan': 'Nissan',
    'hyundai': 'Hyundai',
    'kia': 'Kia',
    'dacia': 'Dacia',
    'skoda': 'Škoda',
    'škoda': 'Škoda',
    'seat': 'SEAT',
    'volvo': 'Volvo',
    'opel': 'Opel',
    'mazda': 'Mazda',
    'tesla': 'Tesla',
  };
  final corrected = makes[enteredMake];
  if (corrected != null) {
    controller.value = TextEditingValue(
      text: '$corrected$remainder',
      selection:
          TextSelection.collapsed(offset: corrected.length + remainder.length),
    );
  }
}
