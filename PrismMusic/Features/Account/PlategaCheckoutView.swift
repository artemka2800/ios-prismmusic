//
//  PlategaCheckoutView.swift
//  PrismMusic
//
//  Premium Checkout sheet implementing the Platega.io secure payment gateway simulation.
//  Provides interactive tab-switching for Credit Card, SBP (QR), and Crypto (TRC-20) payments.
//

import SwiftUI

struct PlategaCheckoutView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum PaymentMethod {
        case card, sbp, crypto
    }

    enum PaymentStep {
        case form
        case processing
        case success
        case error(String)
    }

    // Input States
    @State private var paymentMethod: PaymentMethod = .card
    @State private var paymentStep: PaymentStep = .form
    @State private var cardNumber = ""
    @State private var cardExpiry = ""
    @State private var cardCvc = ""
    @State private var cardName = ""
    @State private var isSubscribing = false
    @State private var walletCopied = false

    var body: some View {
        ZStack {
            // Immersive background mimicking dark mode / glass overlay
            Color(red: 0.05, green: 0.05, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Secure Light effects (mocking CSS glow gradients)
                ZStack {
                    Circle()
                        .fill(Color.emerald.opacity(0.12))
                        .frame(width: 250, height: 250)
                        .blur(radius: 50)
                        .offset(x: -120, y: -100)

                    Circle()
                        .fill(Color.purple.opacity(0.08))
                        .frame(width: 200, height: 200)
                        .blur(radius: 50)
                        .offset(x: 120, y: 180)
                }
                .allowsHitTesting(false)

                // Header
                headerView

                Divider()
                    .background(Color.white.opacity(0.1))

                // Steps content switcher
                switch paymentStep {
                case .form:
                    formStepView
                case .processing:
                    processingStepView
                case .success:
                    successStepView
                case .error(let errorMsg):
                    errorStepView(errorMsg: errorMsg)
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Layout.screenInset)
            .padding(.top, 24)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("БЕЗОПАСНАЯ ОПЛАТА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.emerald)
                    .tracking(1.5)
                
                HStack(spacing: 4) {
                    Text("platega")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)
                    Text(".io")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.emerald)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Сумма к оплате")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("999 ₽")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Form View (Primary UI)
    private var formStepView: some View {
        VStack(spacing: 20) {
            // Payment Method Tabs
            HStack(spacing: 4) {
                methodTabButton(title: "Карта", icon: "creditcard", method: .card)
                methodTabButton(title: "СБП", icon: "qrcode", method: .sbp)
                methodTabButton(title: "Crypto", icon: "bitcoinsign.circle", method: .crypto)
            }
            .padding(4)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )

            // Dynamic Inputs depending on Method
            switch paymentMethod {
            case .card:
                cardFormInputs
            case .sbp:
                sbpFormInputs
            case .crypto:
                cryptoFormInputs
            }
        }
    }

    // MARK: - Tab Button Helper
    private func methodTabButton(title: String, icon: String, method: PaymentMethod) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                paymentMethod = method
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(paymentMethod == method ? .white : Theme.Palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(paymentMethod == method ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Inputs
    private var cardFormInputs: some View {
        VStack(spacing: 16) {
            // Card Number
            VStack(alignment: .leading, spacing: 6) {
                Text("Номер карты")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                
                TextField("0000 0000 0000 0000", text: $cardNumber)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, design: .monospaced))
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .foregroundStyle(.white)
                    .tint(Color.emerald)
                    .onChange(of: cardNumber) { _, newValue in
                        let clean = newValue.replacingOccurrences(of: " ", with: "")
                            .filter { $0.isNumber }
                        let truncated = String(clean.prefix(16))
                        var formatted = ""
                        for (index, char) in truncated.enumerated() {
                            if index > 0 && index % 4 == 0 {
                                formatted.append(" ")
                            }
                            formatted.append(char)
                        }
                        cardNumber = formatted
                    }
            }

            // Expiry & CVC Row
            HStack(spacing: 16) {
                // Expiry
                VStack(alignment: .leading, spacing: 6) {
                    Text("Срок действия")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    
                    TextField("ММ/ГГ", text: $cardExpiry)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16, design: .monospaced))
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .foregroundStyle(.white)
                        .tint(.emerald)
                        .onChange(of: cardExpiry) { _, newValue in
                            let clean = newValue.replacingOccurrences(of: "/", with: "")
                                .filter { $0.isNumber }
                            let truncated = String(clean.prefix(4))
                            if truncated.count >= 2 {
                                cardExpiry = "\(truncated.prefix(2))/\(truncated.suffix(from: truncated.index(truncated.startIndex, offsetBy: 2)))"
                            } else {
                                cardExpiry = truncated
                            }
                        }
                }

                // CVC
                VStack(alignment: .leading, spacing: 6) {
                    Text("CVC / CVV")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    
                    SecureField("•••", text: $cardCvc)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16, design: .monospaced))
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .foregroundStyle(.white)
                        .tint(.emerald)
                        .onChange(of: cardCvc) { _, newValue in
                            let clean = newValue.filter { $0.isNumber }
                            cardCvc = String(clean.prefix(3))
                        }
                }
            }

            // Owner Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Имя владельца карты (Латиница)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                
                TextField("IVAN IVANOV", text: $cardName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 16, weight: .medium))
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .foregroundStyle(.white)
                    .tint(.emerald)
                    .onChange(of: cardName) { _, newValue in
                        let filtered = newValue.filter { char in
                            char.isLetter || char == " "
                        }
                        cardName = filtered.uppercased()
                    }
            }

            // Pay Button
            Button {
                executeSubscriptionPayment()
            } label: {
                Text("Оплатить через Platega")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCardValid ? Color.emerald : Color.emerald.opacity(0.4))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!isCardValid || isSubscribing)
            .padding(.top, 8)
        }
    }

    private var isCardValid: Bool {
        cardNumber.replacingOccurrences(of: " ", with: "").count == 16 &&
        cardExpiry.replacingOccurrences(of: "/", with: "").count == 4 &&
        cardCvc.count == 3 &&
        !cardName.isEmpty
    }

    // MARK: - SBP Inputs
    private var sbpFormInputs: some View {
        VStack(spacing: 20) {
            // Simulated QR Code
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 160, height: 160)
                    .shadow(color: .black.opacity(0.2), radius: 10)

                // Simulated grid matrix representing QR
                VStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<12, id: \.self) { col in
                                Rectangle()
                                    .fill(isQrModuleFilled(row: row, col: col) ? Color.black : Color.clear)
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            VStack(spacing: 4) {
                Text("Быстрый платеж по QR-коду СБП")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Откройте приложение вашего банка, выберите оплату по QR и отсканируйте код выше.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
            }

            Button {
                executeSubscriptionPayment()
            } label: {
                Text("Я оплатил")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.emerald)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isSubscribing)
        }
    }

    private func isQrModuleFilled(row: Int, col: Int) -> Bool {
        // Mock corner finder patterns
        if (row < 4 && col < 4) || (row < 4 && col > 7) || (row > 7 && col < 4) {
            // Hollow corner squares
            if row == 0 || row == 3 || col == 0 || col == 3 ||
               row == 0 || row == 3 || col == 8 || col == 11 ||
               row == 8 || row == 11 || col == 0 || col == 3 {
                return true
            }
            if (row == 1 || row == 2) && (col == 1 || col == 2) { return false }
            if (row == 1 || row == 2) && (col == 9 || col == 10) { return false }
            if (row == 9 || row == 10) && (col == 1 || col == 2) { return false }
        }
        // Pseudo-random math pattern for interior modules
        return (row * 7 + col * 13) % 3 == 0 || (row * col) % 5 == 1
    }

    // MARK: - Crypto Inputs
    private var cryptoFormInputs: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сумма к отправке")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text("10.5 USDT (TRC-20)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("Сеть TRC-20")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.emerald)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.emerald.opacity(0.12))
                        .cornerRadius(20)
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Адрес кошелька получателя")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    
                    HStack(spacing: 8) {
                        Text("TYfV1cWp8H12Jks87sz6qN1")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                        
                        Button {
                            UIPasteboard.general.string = "TYfV1cWp8H12Jks87sz6qN1"
                            withAnimation {
                                walletCopied = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(2.0))
                                withAnimation { walletCopied = false }
                            }
                        } label: {
                            Text(walletCopied ? "Copied" : "Copy")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(walletCopied ? Color.emerald : .white)
                                .padding(.horizontal, 14)
                                .frame(height: 42)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("После совершения перевода нажмите кнопку ниже для автоматического сканирования сети.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)

            Button {
                executeSubscriptionPayment()
            } label: {
                Text("Проверить транзакцию")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.emerald)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isSubscribing)
        }
    }

    // MARK: - Processing Step
    private var processingStepView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .tint(Color.emerald)
                .controlSize(.large)
                .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("Авторизация платежа")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("Проверяем статус транзакции через платежный шлюз Platega.io. Это займет несколько секунд...")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Success Step
    private var successStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.emerald.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.emerald)
            }
            .padding(.top, 30)

            VStack(spacing: 8) {
                Text("Оплата успешно проведена!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("Ваш аккаунт обновлен до статуса Premium. Все ограничения по кастомизации интерфейса сняты.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Error Step
    private func errorStepView(errorMsg: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
            }
            .padding(.top, 30)

            VStack(spacing: 8) {
                Text("Ошибка оплаты")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(errorMsg)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                withAnimation {
                    paymentStep = .form
                }
            } label: {
                Text("Попробовать снова")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Subscription Logic
    private func executeSubscriptionPayment() {
        guard app.settings.isLoggedIn else {
            paymentStep = .error("Для активации подписки необходимо войти в аккаунт.")
            return
        }

        isSubscribing = true
        withAnimation {
            paymentStep = .processing
        }

        Task {
            do {
                // Simulate gateway transaction delay
                try await Task.sleep(for: .seconds(2.2))

                let response = try await app.api.subscribe(userId: app.settings.userId, action: "subscribe")
                
                if let role = response.role, role == "premium" || role == "admin" || role == "creator" {
                    app.settings.role = role
                    
                    withAnimation {
                        paymentStep = .success
                    }

                    // Auto dismiss after brief delay showing success
                    try? await Task.sleep(for: .seconds(2.2))
                    dismiss()
                } else {
                    throw APIError.invalidResponse
                }
            } catch {
                withAnimation {
                    paymentStep = .error("Не удалось подтвердить транзакцию через Platega.io: \(error.localizedDescription)")
                }
            }
            isSubscribing = false
        }
    }
}
