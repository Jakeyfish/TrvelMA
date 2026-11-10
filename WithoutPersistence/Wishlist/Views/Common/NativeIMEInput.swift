import SwiftUI
import UIKit

func numericTextFieldWidth(for value: String, placeholder: String) -> CGFloat {
    let visibleValue = value.isEmpty ? placeholder : value
    let estimatedWidth = CGFloat(max(visibleValue.count, 1)) * 9 + 12
    return min(max(estimatedWidth, 28), 144)
}

/// UIKit text input that keeps uncommitted pinyin/Wubi composition inside the system field.
struct SystemIMETextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: UITextAutocapitalizationType = .sentences
    var autocorrection: UITextAutocorrectionType = .default
    var textContentType: UITextContentType?
    var clearsZeroOnFocus: Bool = true
    var textAlignment: TextAlignment = .leading
    var fontSize: CGFloat = 17
    var isFocused: Binding<Bool>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectsOrClearsOnFocus: keyboardType == .numberPad || keyboardType == .decimalPad || keyboardType == .phonePad,
            clearsZeroOnFocus: clearsZeroOnFocus && (keyboardType == .numberPad || keyboardType == .decimalPad),
            isFocused: isFocused
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // UITextField's intrinsic width can follow a long value. In an HStack,
        // report only the width the parent offers so text scrolls inside the
        // field instead of widening the entire form.
        CGSize(
            width: proposal.width ?? 0,
            height: proposal.height ?? max(uiView.intrinsicContentSize.height, 1)
        )
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        context.coordinator.textField = field
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.autocapitalizationType = capitalization
        field.autocorrectionType = autocorrection
        field.textContentType = textContentType
        field.textAlignment = textAlignment == .trailing ? .right : .left
        field.delegate = context.coordinator
        field.inputAccessoryView = KeyboardDoneAccessory.make(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.font = .systemFont(ofSize: fontSize)
        field.accessibilityLabel = placeholder
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.selectsOrClearsOnFocus = keyboardType == .numberPad || keyboardType == .decimalPad || keyboardType == .phonePad
        context.coordinator.clearsZeroOnFocus = clearsZeroOnFocus && (keyboardType == .numberPad || keyboardType == .decimalPad)
        if field.placeholder != placeholder { field.placeholder = placeholder }
        if field.keyboardType != keyboardType { field.keyboardType = keyboardType }
        if field.autocapitalizationType != capitalization { field.autocapitalizationType = capitalization }
        if field.autocorrectionType != autocorrection { field.autocorrectionType = autocorrection }
        if field.textContentType != textContentType { field.textContentType = textContentType }
        let alignment: NSTextAlignment = textAlignment == .trailing ? .right : .left
        if field.textAlignment != alignment { field.textAlignment = alignment }
        if field.font?.pointSize != fontSize { field.font = .systemFont(ofSize: fontSize) }
        if isFocused?.wrappedValue == true, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if isFocused?.wrappedValue == false,
                  context.coordinator.hasObservedFocus,
                  field.isFirstResponder {
            field.resignFirstResponder()
        }
        // Never replace the text while iOS is composing a pinyin/Wubi candidate.
        guard field.markedTextRange == nil, field.text != text else { return }
        field.text = text
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var selectsOrClearsOnFocus: Bool
        var clearsZeroOnFocus: Bool
        var isFocused: Binding<Bool>?
        var hasObservedFocus = false
        weak var textField: UITextField?

        init(text: Binding<String>, selectsOrClearsOnFocus: Bool = false, clearsZeroOnFocus: Bool = true, isFocused: Binding<Bool>? = nil) {
            self.text = text
            self.selectsOrClearsOnFocus = selectsOrClearsOnFocus
            self.clearsZeroOnFocus = clearsZeroOnFocus
            self.isFocused = isFocused
        }

        @objc func editingChanged(_ field: UITextField) {
            updateBinding(from: field)
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            updateBinding(from: field)
        }

        @objc func dismissKeyboard() { textField?.resignFirstResponder() }

        func textFieldDidBeginEditing(_ field: UITextField) {
            hasObservedFocus = true
            if isFocused?.wrappedValue != true { isFocused?.wrappedValue = true }
            guard selectsOrClearsOnFocus,
                  let currentValue = field.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !currentValue.isEmpty else { return }

            let formatter = NumberFormatter()
            formatter.locale = .current
            let numericValue = formatter.number(from: currentValue)?.doubleValue ?? Double(currentValue)
            if clearsZeroOnFocus, let numericValue, abs(numericValue) < 0.000_000_1 {
                field.text = ""
                if !text.wrappedValue.isEmpty { text.wrappedValue = "" }
                return
            }

            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder,
                      let end = field.position(from: field.beginningOfDocument, offset: field.text?.utf16.count ?? 0) else { return }
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: end)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            hasObservedFocus = false
            if isFocused?.wrappedValue != false { isFocused?.wrappedValue = false }
        }

        private func updateBinding(from field: UITextField) {
            guard field.markedTextRange == nil else { return }
            let value = field.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}

/// Flight numbers use a dedicated keyboard with uppercase letters and digits only.
struct FlightNumberTextField: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 14

    private var doneTitle: String {
        let language = locale.identifier.lowercased()
        if language.hasPrefix("en") { return "Done" }
        if language.hasPrefix("es") { return "Listo" }
        if language.hasPrefix("ja") { return "完了" }
        if language.hasPrefix("ko") { return "완료" }
        return "完成"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        context.coordinator.textField = field
        field.placeholder = placeholder
        field.keyboardType = .asciiCapable
        field.inputView = Self.makeFlightKeyboard(target: context.coordinator)
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.delegate = context.coordinator
        field.inputAccessoryView = Self.makeAccessory(target: context.coordinator, doneTitle: doneTitle)
        field.font = .systemFont(ofSize: fontSize)
        field.text = Self.normalized(text)
        field.accessibilityLabel = placeholder
        return field
    }

    static func makeFlightKeyboard(target: Coordinator) -> UIInputView {
        let keyboard = UIInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 260), inputViewStyle: .keyboard)
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        keyboard.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: keyboard.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            rows.trailingAnchor.constraint(equalTo: keyboard.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            rows.topAnchor.constraint(equalTo: keyboard.topAnchor, constant: 8),
            rows.bottomAnchor.constraint(equalTo: keyboard.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        rows.distribution = .fillEqually
        let keyRows = ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "⌄ZXCVBNM⌫"]
        for characters in keyRows {
            let keys = characters.map { String($0) }
            let row = UIStackView()
            row.spacing = 5
            row.distribution = .fillEqually
            for key in keys {
                let button = UIButton(type: .system)
                button.setTitle(key, for: .normal)
                button.setTitleColor(.label, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 22)
                button.backgroundColor = .secondarySystemGroupedBackground
                button.layer.cornerRadius = 6
                button.accessibilityLabel = key == "⌫" ? String(localized: "删除") : key == "⌄" ? String(localized: "收起键盘") : key
                button.addTarget(target, action: #selector(Coordinator.pressFlightKey(_:)), for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            rows.addArrangedSubview(row)
        }
        return keyboard
    }

    private static func makeAccessory(target: Coordinator, doneTitle: String) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: doneTitle, style: .done, target: target, action: #selector(Coordinator.dismissKeyboard))
        ]
        toolbar.sizeToFit()
        return toolbar
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: fontSize)
        guard !field.isFirstResponder else { return }
        let value = Self.normalized(text)
        if field.text != value { field.text = value }
    }

    private static func normalized(_ value: String) -> String {
        String(value.unicodeScalars.compactMap { scalar in
            switch scalar.value {
            case 48...57, 65...90: return Character(scalar)
            case 97...122: return Character(scalar).uppercased().first
            default: return nil
            }
        })
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        weak var textField: UITextField?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func dismissKeyboard() { textField?.resignFirstResponder() }

        @objc func pressFlightKey(_ sender: UIButton) {
            guard let key = sender.title(for: .normal), let field = textField else { return }
            if key == "⌄" { dismissKeyboard(); return }
            if key == "⌫" {
                var range = selectedRange(in: field)
                if range.length == 0 {
                    guard range.location > 0 else { return }
                    range.location -= 1
                    range.length = 1
                }
                replace(range, in: field.text ?? "", with: "")
            } else { replaceSelection(with: key) }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString replacement: String) -> Bool {
            replace(range, in: textField.text ?? "", with: replacement)
            return false
        }

        private func replaceSelection(with replacement: String) {
            guard let field = textField, let current = field.text else { return }
            replace(selectedRange(in: field), in: current, with: replacement)
        }

        private func selectedRange(in field: UITextField) -> NSRange {
            guard let selection = field.selectedTextRange else {
                return NSRange(location: (field.text ?? "").utf16.count, length: 0)
            }
            let location = field.offset(from: field.beginningOfDocument, to: selection.start)
            let length = field.offset(from: selection.start, to: selection.end)
            return NSRange(location: location, length: length)
        }

        private func replace(_ range: NSRange, in current: String, with replacement: String) {
            let nsCurrent = current as NSString
            let safeRange = NSRange(location: min(range.location, nsCurrent.length), length: min(range.length, max(0, nsCurrent.length - range.location)))
            let prefix = nsCurrent.substring(to: safeRange.location)
            let suffix = nsCurrent.substring(from: safeRange.location + safeRange.length)
            let inserted = Self.normalized(replacement)
            let updated = prefix + inserted + suffix
            textField?.text = updated
            if text.wrappedValue != updated { text.wrappedValue = updated }
            if let field = textField,
               let caret = field.position(from: field.beginningOfDocument, offset: safeRange.location + inserted.utf16.count) {
                field.selectedTextRange = field.textRange(from: caret, to: caret)
            }
        }

        private static func normalized(_ value: String) -> String {
            String(value.unicodeScalars.compactMap { scalar -> Character? in
                switch scalar.value {
                case 48...57, 65...90: return Character(scalar)
                case 97...122: return Character(scalar).uppercased().first
                default: return nil
                }
            })
        }
    }
}

extension View {
    /// Marks a text input as using iOS's active system input method.
    func nativeIMEInput() -> some View {
        self
    }

    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbarModifier())
    }
}

private struct KeyboardDoneToolbarModifier: ViewModifier {
    @Environment(\.locale) private var locale

    private var doneTitle: String {
        let language = locale.identifier.lowercased()
        if language.hasPrefix("en") { return "Done" }
        if language.hasPrefix("es") { return "Listo" }
        if language.hasPrefix("ja") { return "完了" }
        if language.hasPrefix("ko") { return "완료" }
        if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") { return "完成" }
        return "完成"
    }

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(doneTitle) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

private enum KeyboardDoneAccessory {
    private static var doneTitle: String {
        let language = AppLanguageSettings.effectiveIdentifier.lowercased()
        if language.hasPrefix("en") { return "Done" }
        if language.hasPrefix("es") { return "Listo" }
        if language.hasPrefix("ja") { return "完了" }
        if language.hasPrefix("ko") { return "완료" }
        return "完成"
    }

    static func make(target: AnyObject, action: Selector) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: doneTitle, style: .done, target: target, action: action)
        ]
        return toolbar
    }
}

/// A system text view that applies its character limit only after IME composition commits.
struct LimitedIMETextEditor: UIViewRepresentable {
    @Binding var text: String
    let maxLength: Int
    var fontSize: CGFloat = 17
    var placeholder: String = ""
    var isFocused: Binding<Bool>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maxLength: maxLength, isFocused: isFocused)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Constrain the representable to its parent's width; UITextView's
        // intrinsic content size must not make a containing form scroll sideways.
        CGSize(
            width: proposal.width ?? 0,
            height: proposal.height ?? max(uiView.font?.lineHeight ?? 20, 1)
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        context.coordinator.textView = view
        view.delegate = context.coordinator
        view.inputAccessoryView = KeyboardDoneAccessory.make(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        view.font = .systemFont(ofSize: fontSize)
        view.backgroundColor = .clear
        view.text = text
        let placeholderLabel = UILabel()
        placeholderLabel.tag = 9_731
        placeholderLabel.text = placeholder
        placeholderLabel.font = .systemFont(ofSize: fontSize)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: view.textContainerInset.left + 5),
            placeholderLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -view.textContainerInset.right - 5),
            placeholderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: view.textContainerInset.top)
        ])
        placeholderLabel.isHidden = !text.isEmpty
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.maxLength = maxLength
        context.coordinator.isFocused = isFocused
        view.font = .systemFont(ofSize: fontSize)
        if let placeholderLabel = view.viewWithTag(9_731) as? UILabel {
            placeholderLabel.text = placeholder
            placeholderLabel.font = .systemFont(ofSize: fontSize)
            placeholderLabel.isHidden = !text.isEmpty
        }
        if view.markedTextRange == nil, view.text != text {
            view.text = text
        }
        if isFocused?.wrappedValue == true, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if isFocused?.wrappedValue == false, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var maxLength: Int
        var isFocused: Binding<Bool>?
        weak var textView: UITextView?

        init(text: Binding<String>, maxLength: Int, isFocused: Binding<Bool>?) {
            self.text = text
            self.maxLength = maxLength
            self.isFocused = isFocused
        }

        @objc func dismissKeyboard() { textView?.resignFirstResponder() }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if isFocused?.wrappedValue != true { isFocused?.wrappedValue = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFocused?.wrappedValue != false { isFocused?.wrappedValue = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            // Keep pinyin/Wubi marked text intact until iOS commits the composition.
            guard textView.markedTextRange == nil else { return }
            let value = textView.text ?? ""
            let limitedValue = String(value.prefix(maxLength))
            if limitedValue != value {
                textView.text = limitedValue
            }
            (textView.viewWithTag(9_731) as? UILabel)?.isHidden = !limitedValue.isEmpty
            if text.wrappedValue != limitedValue {
                text.wrappedValue = limitedValue
            }
        }
    }
}

/// Numeric amount entry that selects the current value on focus, or clears zero.
/// Parses a complete locale-formatted amount, rejecting trailing junk and malformed grouping.
enum SettlementAmountInput {
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let value = trimmed.map { character -> String in
            if character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
               let digit = character.wholeNumberValue { return String(digit) }
            return String(character)
        }.joined()
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = formatter.decimalSeparator ?? "."
        let grouping = formatter.groupingSeparator ?? ""
        let primary = max(1, formatter.groupingSize)
        let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
        let escapedDecimal = NSRegularExpression.escapedPattern(for: decimal)
        var integer = "[0-9]+"
        if !grouping.isEmpty && grouping != decimal {
            let separator = NSRegularExpression.escapedPattern(for: grouping)
            integer = "(?:[0-9]+|[0-9]{1,\(secondary)}(?:\(separator)[0-9]{\(secondary)})*\(separator)[0-9]{\(primary)})"
        }
        let pattern = "^[+-]?(?:\(integer)(?:\(escapedDecimal)[0-9]*)?|\(escapedDecimal)[0-9]+)$"
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        var normalized = value
        if !grouping.isEmpty { normalized = normalized.replacingOccurrences(of: grouping, with: "") }
        normalized = normalized.replacingOccurrences(of: decimal, with: ".")
        guard let amount = Double(normalized), amount.isFinite else { return nil }
        return amount
    }
}

struct AmountTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var value: Double
    var fontSize: CGFloat = 17
    var onValidityChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        context.coordinator.textField = field
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.font = .systemFont(ofSize: fontSize)
        field.placeholder = placeholder
        field.delegate = context.coordinator
        field.inputAccessoryView = KeyboardDoneAccessory.make(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        field.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .editingChanged)
        field.text = Self.displayValue(value)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: fontSize)
        guard !field.isFirstResponder, !context.coordinator.hasInvalidText else { return }
        let formattedValue = Self.displayValue(value)
        if field.text != formattedValue { field.text = formattedValue }
    }

    private static func displayValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountTextField
        weak var textField: UITextField?
        var hasInvalidText = false

        init(_ parent: AmountTextField) {
            self.parent = parent
        }

        @objc func dismissKeyboard() { textField?.resignFirstResponder() }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !hasInvalidText && abs(parent.value) < 0.000_000_1 {
                textField.text = ""
            } else {
                DispatchQueue.main.async { [weak textField] in
                    guard let textField, let text = textField.text, !text.isEmpty,
                          let start = textField.position(from: textField.beginningOfDocument, offset: 0),
                          let end = textField.position(from: textField.beginningOfDocument, offset: text.utf16.count) else { return }
                    textField.selectedTextRange = textField.textRange(from: start, to: end)
                }
            }
        }

        @objc func valueChanged(_ textField: UITextField) {
            if let onValidityChange = parent.onValidityChange {
                guard let amount = SettlementAmountInput.parse(textField.text ?? "") else {
                    hasInvalidText = true
                    onValidityChange(false)
                    return
                }
                hasInvalidText = false
                parent.value = amount
                onValidityChange(true)
                return
            }
            guard let text = textField.text, !text.isEmpty else {
                parent.value = 0
                return
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let number = formatter.number(from: text) {
                parent.value = number.doubleValue
                return
            }
            let separator = Locale.current.decimalSeparator ?? "."
            let normalized = text.replacingOccurrences(of: separator, with: ".")
            if let number = Double(normalized) { parent.value = number }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            valueChanged(textField)
        }
    }
}
