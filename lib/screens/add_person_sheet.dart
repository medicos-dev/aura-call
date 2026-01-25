import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';

class AddPersonSheet extends StatefulWidget {
  final Function(String callId) onAdd;

  const AddPersonSheet({super.key, required this.onAdd});

  @override
  State<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends State<AddPersonSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isValid = _controller.text.length == 6;
      });
    });

    // Auto focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleAdd() {
    if (_isValid) {
      widget.onAdd(_controller.text.toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate bottom padding for safe area
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Proper safe area spacing at bottom
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: bottomPadding + keyboardHeight + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppTheme.buttonGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_add,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Person',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Enter their 6-digit call ID',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Input field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isValid ? AppTheme.success : AppTheme.surfaceBorder,
                width: _isValid ? 2 : 1,
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'CALL ID',
                hintStyle: TextStyle(
                  color: AppTheme.textMuted,
                  letterSpacing: 4,
                  fontSize: 20,
                ),
                border: InputBorder.none,
                counterText: '',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                UpperCaseTextFormatter(),
              ],
              onSubmitted: (_) => _handleAdd(),
            ),
          ),
          const SizedBox(height: 8),

          // Helper text
          Center(
            child: Text(
              '${_controller.text.length}/6 characters',
              style: TextStyle(
                color: _isValid ? AppTheme.success : AppTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Add button
          GestureDetector(
            onTap: _isValid ? _handleAdd : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: _isValid ? AppTheme.buttonGradient : null,
                color: _isValid ? null : AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    _isValid
                        ? [
                          BoxShadow(
                            color: AppTheme.primaryPurple.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ]
                        : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_call,
                    color: _isValid ? Colors.white : AppTheme.textMuted,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add to Call',
                    style: TextStyle(
                      color: _isValid ? Colors.white : AppTheme.textMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Extra spacing for safe area
          SizedBox(height: bottomPadding > 0 ? 8 : 0),
        ],
      ),
    );
  }
}

/// Text formatter for uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
