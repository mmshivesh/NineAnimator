//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2019 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import AuthenticationServices
import SafariServices
import UIKit

class TrackingServiceTableViewController: UITableViewController {
    // AniList
    @IBOutlet private weak var anilistStatusLabel: UILabel!
    @IBOutlet private weak var anilistActionLabel: UILabel!
    @IBOutlet private weak var anilistPushNineAnimatorUpdatesSwitch: UISwitch!
    private var anilistAccountInfoFetchTask: NineAnimatorAsyncTask?
    
    // Kitsu.io
    @IBOutlet private weak var kitsuStatusLabel: UILabel!
    @IBOutlet private weak var kitsuActionLabel: UILabel!
    @IBOutlet private weak var kitsuPushNineAnimatorUpdatesSwitch: UISwitch!
    private var kitsuAuthenticationTask: NineAnimatorAsyncTask?
    private var kitsuAccountInfoFetchTask: NineAnimatorAsyncTask?
    
    // Preserve a reference to the authentication session
    private var authenticationSessionReference: AnyObject?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Update status
        anilistUpdateStatus()
        kitsuUpdateStatus()
        tableView.makeThemable()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectSelectedRow() }
        
        // Retrieve reuse identifier
        guard let cell = tableView.cellForRow(at: indexPath),
            let identifier = cell.reuseIdentifier else {
            return
        }
        
        switch identifier {
        case "service.anilist.action":
            if anilist.didExpire || !anilist.didSetup {
                anilistPresentAuthenticationPage()
            } else { anilistLogOut() }
        case "service.kitsu.action":
            if kitsu.didExpire || !kitsu.didSetup {
                kitsuPresentAuthenticationPage()
            } else { kitsuLogout() }
        default:
            Log.info("An unimplemented cell with identifier \"%@\" was selected", identifier)
        }
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let cell = tableView.cellForRow(at: indexPath) else { return indexPath }
        
        // Disable the action cell if there is a task running
        if cell.reuseIdentifier == "service.kitsu.action",
            kitsuAuthenticationTask != nil {
            return nil
        }
        
        return indexPath
    }
}

extension TrackingServiceTableViewController {
    private var kitsu: Kitsu { return NineAnimator.default.service(type: Kitsu.self) }
    
    private func kitsuPresentAuthenticationPage() {
        let alert = UIAlertController(
            title: "Setup Kitsu.io",
            message: "Login to Kitsu.io with your email and password.",
            preferredStyle: .alert
        )
        
        // Email field
        alert.addTextField {
            $0.placeholder = "example@example.com"
            $0.textContentType = .emailAddress
        }
        
        // Password field
        alert.addTextField {
            $0.placeholder = "Password"
            $0.textContentType = .password
            $0.isSecureTextEntry = true
        }
        
        alert.addAction(UIAlertAction(title: "Login", style: .default) {
            [unowned kitsu, weak self] _ in
            guard let self = self else { return }
            
            // Obtain username and password values
            guard let user = alert.textFields?.first?.text,
                let password = alert.textFields?.last?.text else {
                return
            }
            
            // Authenticate with the provided username and password
            self.kitsuAuthenticationTask = kitsu.authenticate(user: user, password: password).error {
                [weak self] error in
                let message: String
                if let error = error as? NineAnimatorError {
                    if case .authenticationRequiredError = error {
                        message = "Your email or password was incorrect"
                    } else { message = error.description }
                } else { message = error.localizedDescription }
                
                // Present the error message
                let errorAlert = UIAlertController(title: "Authentication Error", message: message, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "Ok", style: .cancel))
                self?.kitsuAuthenticationTask = nil
                
                DispatchQueue.main.async {
                    self?.present(errorAlert, animated: true)
                    self?.kitsuUpdateStatus()
                }
            } .finally {
                [weak self] in
                Log.info("Successfully logged in to Kitsu.io")
                self?.kitsuAuthenticationTask = nil
                DispatchQueue.main.async { self?.kitsuUpdateStatus() }
            }
            self.kitsuUpdateStatus()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func kitsuLogout() {
        kitsu.deauthenticate()
        kitsuUpdateStatus()
    }
    
    private func kitsuUpdateStatus() {
        // First, tint the action label
        kitsuActionLabel.textColor = Theme.current.tint
        
        // Disable the push update switch, since kitsu is implemented as a track-only service
        kitsuPushNineAnimatorUpdatesSwitch.isEnabled = false
        kitsuPushNineAnimatorUpdatesSwitch.setOn(kitsu.didSetup && !kitsu.didExpire, animated: true)
        
        if kitsu.didSetup {
            if kitsu.didExpire {
                kitsuStatusLabel.text = "Expired"
                kitsuActionLabel.text = "Authenticate Kitsu.io"
            } else {
                kitsuStatusLabel.text = "Updating"
                kitsuActionLabel.text = "Sign Out"
                
                // Fetch current user info
                kitsuAccountInfoFetchTask = kitsu.currentUser().error {
                    [weak kitsuStatusLabel] _ in DispatchQueue.main.async {
                        kitsuStatusLabel?.text = "Error"
                    }
                } .finally {
                    [weak kitsuStatusLabel] user in DispatchQueue.main.async {
                        kitsuStatusLabel?.text = "Signed in as \(user.name)"
                    }
                }
            }
        } else if kitsuAuthenticationTask != nil {
            kitsuStatusLabel.text = "Updating"
            kitsuActionLabel.text = "Signing you in..."
            kitsuActionLabel.textColor = Theme.current.secondaryText
        } else {
            kitsuStatusLabel.text = "Not Setup"
            kitsuActionLabel.text = "Setup Kitsu.io"
        }
    }
}

// MARK: - AniList.co specifics
extension TrackingServiceTableViewController {
    private var anilist: Anilist { return NineAnimator.default.service(type: Anilist.self) }
    
    private func anilistUpdateStatus() {
        // Disable switch by default
        anilistPushNineAnimatorUpdatesSwitch.setOn(false, animated: true)
        anilistPushNineAnimatorUpdatesSwitch.isEnabled = false
        
        if anilist.didSetup {
            if anilist.didExpire {
                anilistStatusLabel.text = "Expired"
                anilistActionLabel.text = "Authenticate AniList.co"
            } else {
                anilistStatusLabel.text = "Loading..."
                anilistActionLabel.text = "Sign Out"
                
                let updateStatusLabel = {
                    text in
                    DispatchQueue.main.async { [weak self] in self?.anilistStatusLabel.text = text }
                }
                
                anilistAccountInfoFetchTask = anilist.currentUser()
                    .error { _ in updateStatusLabel("Error") }
                    .finally { updateStatusLabel("Signed in as \($0.name)") }
                
                // Update the state accordingly
                anilistPushNineAnimatorUpdatesSwitch.setOn(anilist.isTrackingEnabled, animated: true)
                anilistPushNineAnimatorUpdatesSwitch.isEnabled = true
            }
        } else { // Present initial setup labels
            anilistStatusLabel.text = "Not Setup"
            anilistActionLabel.text = "Setup AniList.co"
        }
    }
    
    @IBAction private func anilistOnPushNineAnimatorUpdatesToggled(_ sender: UISwitch) {
        anilist.isTrackingEnabled = sender.isOn
    }
    
    // Present the SSO login page
    private func anilistPresentAuthenticationPage() {
        let callback: NineAnimatorCallback<URL> = {
            [weak anilist, weak self] url, callbackError in
            defer { DispatchQueue.main.async { [weak self] in self?.anilistUpdateStatus() } }
            var error = callbackError
            
            // If callback url is provided
            if let url = url {
                error = anilist?.authenticate(with: url)
            }
            
            // If an error is present
            if let error = error {
                Log.error("[AniList.co] Authentication session finished with error: %@", error)
            }
        }
        
        // Open the authentication dialog/web page
        if #available(iOS 12.0, *) {
            let session = ASWebAuthenticationSession(url: anilist.ssoUrl, callbackURLScheme: anilist.ssoCallbackScheme, completionHandler: callback)
            _ = session.start()
            authenticationSessionReference = session
        } else {
            let session = SFAuthenticationSession(url: anilist.ssoUrl, callbackURLScheme: anilist.ssoCallbackScheme, completionHandler: callback)
            _ = session.start()
            authenticationSessionReference = session
        }
    }
    
    // Tell AniList service to logout
    private func anilistLogOut() {
        anilist.deauthenticate()
        anilistUpdateStatus()
    }
}