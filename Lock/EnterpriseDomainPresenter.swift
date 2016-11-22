// EnterpriseDomainPresenter.swift
//
// Copyright (c) 2016 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

class EnterpriseDomainPresenter: Presentable, Loggable {

    var interactor: EnterpriseDomainInteractor
    var customLogger: Logger?
    var user: User
    var options: Options

    // Social connections
    var authPresenter: AuthPresenter?

    init(interactor: EnterpriseDomainInteractor, navigator: Navigable, user: User, options: Options) {
        self.interactor = interactor
        self.navigator = navigator
        self.user = user
        self.options = options
    }

    var messagePresenter: MessagePresenter?
    var navigator: Navigable?

    var view: View {
        let email = self.interactor.validEmail ? self.interactor.email : nil
        let authCollectionView = self.authPresenter?.newViewToEmbed(withInsets: UIEdgeInsetsMake(0, 0, 0, 0), isLogin: true)

        // Single Enterprise Domain
        if let enterpriseButton = EnterpriseButton(forConnections: interactor.connections, customStyle: [:], isLogin: true, onAction: {
            self.interactor.login { error in
                Queue.main.async {
                    if let error = error {
                        self.messagePresenter?.showError(error)
                        self.logger.error("Enterprise connection failed: \(error)")
                    } else {
                        self.logger.debug("Enterprise authenticator launched")
                    }
                }

        }}) {
            let view = EnterpriseDomainView(authButton: enterpriseButton, authCollectionView: authCollectionView)
            return view
        }

        let view = EnterpriseDomainView(email: email, authCollectionView: authCollectionView)
        let form = view.form

        view.ssoBar?.hidden = self.interactor.connection == nil
        view.form?.onValueChange = { input in
            self.messagePresenter?.hideCurrent()
            view.ssoBar?.hidden = true

            guard case .Email = input.type else { return }
            do {
                try self.interactor.updateEmail(input.text)
                self.user.email = self.interactor.email
                input.showValid()
                if let connection = self.interactor.connection {
                    self.logger.debug("Enterprise connection match: \(connection)")
                    view.ssoBar?.hidden = false
                }
            } catch {
                input.showError()
            }
        }

        let action = { (button: PrimaryButton) in
            // Check for credential auth
            if let connection = self.interactor.connection where self.options.enterpriseConnectionUsingActiveAuth.contains(connection.name) {
                guard self.navigator?.navigate(.EnterpriseActiveAuth(connection: connection)) == nil else { return }
            }
            
            self.messagePresenter?.hideCurrent()
            self.logger.info("Enterprise connection started: \(self.interactor.email), \(self.interactor.connection)")
            let interactor = self.interactor
            button.inProgress = true
            interactor.login { error in
                Queue.main.async {
                    button.inProgress = false
                    form?.needsToUpdateState()
                    if let error = error {
                        self.messagePresenter?.showError(error)
                        self.logger.error("Enterprise connection failed: \(error)")
                    } else {
                        self.logger.debug("Enterprise authenticator launched")
                    }
                }

            }

        }

        view.primaryButton?.onPress = action
        view.form?.onReturn = {_ in
            guard let button = view.primaryButton else { return }
            action(button)
        }

        return view
    }

    func authModeSwitch() -> Bool {
        // Check for credential auth
        if let connection = self.interactor.connection {
            if self.options.enterpriseConnectionUsingActiveAuth.contains(connection.name) {
                self.navigator?.navigate(.EnterpriseActiveAuth(connection: connection))
                return true
            }
        }
        return false
    }

}

func EnterpriseButton(forConnections connections: [EnterpriseConnection], customStyle: [String: AuthStyle], isLogin login: Bool, onAction: () -> () ) -> AuthButton? {
    guard let connection = connections.first where connections.count == 1 else { return nil }
    let style = customStyle[connection.name] ?? connection.style
    style.name = connection.domains.first!
    let button = AuthButton(size: .Big)
    button.title = login ? style.localizedLoginTitle.uppercaseString : style.localizedSignUpTitle.uppercaseString
    button.normalColor = style.normalColor
    button.highlightedColor = style.highlightedColor
    button.titleColor = style.foregroundColor
    button.icon = style.image.image(compatibleWithTraits: button.traitCollection)
    button.onPress = { _ in
        onAction()
    }
    return button
}
