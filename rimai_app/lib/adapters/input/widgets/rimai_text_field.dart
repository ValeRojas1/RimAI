import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RimAITextField extends StatefulWidget {
  final String label;
  final String placeholder;
  final IconData prefixIcon;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool showToggle;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const RimAITextField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.prefixIcon,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.showToggle = false,
    this.errorText,
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<RimAITextField> createState() => _RimAITextFieldState();
}

class _RimAITextFieldState extends State<RimAITextField> {
  late bool _obscureText;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            widget.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF63524E),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // TextField
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFFB8D6B2).withValues(alpha: 0.3),
                      blurRadius: 0,
                      spreadRadius: 4,
                    )
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: widget.keyboardType,
            obscureText: _obscureText,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: const Color(0xFF63524E),
            ),
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                color: const Color(0xFF9E8A84).withValues(alpha: 0.7),
              ),
              prefixIcon: Icon(
                widget.prefixIcon,
                color: const Color(0xFF9E8A84),
                size: 20,
              ),
              suffixIcon: widget.showToggle
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                      child: Icon(
                        _obscureText ? Icons.visibility_off : Icons.visibility,
                        color: !_obscureText
                            ? const Color(0xFFB8D6B2)
                            : const Color(0xFF9E8A84),
                        size: 20,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: _isFocused
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFFE5DED5).withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFB8D6B2),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        // Error Message
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    widget.errorText!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFFB3261E),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
