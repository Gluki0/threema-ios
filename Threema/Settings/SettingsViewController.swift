//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2023 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import CocoaLumberjackSwift
import Foundation
import SwiftUI
import ThreemaFramework

class SettingsViewController: ThemedTableViewController {
    @IBOutlet var feedbackCell: UITableViewCell!
    @IBOutlet var devModeCell: UITableViewCell!

    @IBOutlet var privacyCell: UITableViewCell!
    @IBOutlet var appearanceCell: UITableViewCell!
    @IBOutlet var notificationCell: UITableViewCell!
    @IBOutlet var chatCell: UITableViewCell!
    @IBOutlet var mediaCell: UITableViewCell!
    @IBOutlet var storageManagementCell: UITableViewCell!
    @IBOutlet var passcodeLockCell: UITableViewCell!
    @IBOutlet var threemaCallsCell: UITableViewCell!
    @IBOutlet var threemaWebCell: UITableViewCell!
    @IBOutlet var multiDeviceCell: UITableViewCell!
    @IBOutlet var networkStatusCell: UITableViewCell!
    @IBOutlet var versionCell: UITableViewCell!
    @IBOutlet var usernameCell: UITableViewCell!
    @IBOutlet var inviteAFriendCell: UITableViewCell!
    @IBOutlet var threemaChannelCell: UITableViewCell!
    @IBOutlet var threemaWorkCell: UITableViewCell!
    @IBOutlet var supportCell: UITableViewCell!
    @IBOutlet var privacyPolicyCell: UITableViewCell!
    @IBOutlet var licenseCell: UITableViewCell!
    @IBOutlet var advancedCell: UITableViewCell!
    @IBOutlet var tosCell: UITableViewCell!

    @IBOutlet var usernameCellLabel: UILabel!
    @IBOutlet var userNameCellDetailLabel: UILabel!
    
    private var inviteController: InviteController?
    private var observing = false
    private lazy var lockScreen = LockScreen(isLockScreenController: false)
    override var shouldAutorotate: Bool {
        true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .allButUpsideDown
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
              
        versionCell.detailTextLabel?.text = ThreemaUtility.appAndBuildVersionPretty
        if let versionCopyLabel = versionCell.detailTextLabel as? CopyLabel {
            versionCopyLabel.textForCopying = ThreemaUtility.appAndBuildVersion
        }
        
        userNameCellDetailLabel?.text = LicenseStore.shared().licenseUsername
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorThemeChanged),
            name: NSNotification.Name(rawValue: kNotificationColorThemeChanged),
            object: nil
        )
        BrandingUtils.updateTitleLogo(of: navigationItem, in: navigationController)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateTitleLabels()
        
        updateConnectionStatus()
        updatePasscodeLock()
        updateThreemaWeb()
        updateMultiDevice()
        
        registerObserver()
        
        navigationItem.largeTitleDisplayMode = UINavigationItem
            .LargeTitleDisplayMode(rawValue: (UserSettings.shared()?.largeTitleDisplayMode)!)!
        
        // For the target OnPrem are "Privacy Policy" and "Terms of Service" hidden
        if LicenseStore.isOnPrem() {
            tosCell.isHidden = true
            privacyPolicyCell.isHidden = true
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unregisterObserver()
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == "ThreemaWorkSegue" {
            let appURL = URL(string: "threemawork://app")
            if UIApplication.shared.canOpenURL(appURL!) {
                UIApplication.shared.open(appURL!, options: [:], completionHandler: nil)
                return false
            }
        }
        return true
    }
    
    @objc func colorThemeChanged(notification: Notification) {
        BrandingUtils.updateTitleLogo(of: navigationItem, in: navigationController)
        // set large title color for settingsviewcontroller; it will not automaticly change the color when set new appearance
        navigationController?.navigationBar
            .largeTitleTextAttributes = [NSAttributedString.Key.foregroundColor: Colors.text]
    }
}

extension SettingsViewController {
    // MARK: Private Functions
    
    private func registerObserver() {
        if observing == false {
            ServerConnector.shared().registerConnectionStateDelegate(delegate: self)
            WCSessionManager.shared.addObserver(self, forKeyPath: "running", options: [], context: nil)
            observing = true
        }
    }
    
    private func unregisterObserver() {
        if observing == true {
            ServerConnector.shared().unregisterConnectionStateDelegate(delegate: self)
            WCSessionManager.shared.removeObserver(self, forKeyPath: "running")
            observing = false
        }
    }
    
    private func updateTitleLabels() {
        
        let suffix = Colors.theme == .dark ? "Dark" : "Light"
        
        privacyCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_privacy")
        privacyCell.imageView?.image = BundleUtil.imageNamed("Privacy\(suffix)")
        
        appearanceCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_appearance")
        appearanceCell.imageView?.image = BundleUtil.imageNamed("Appearance\(suffix)")
        
        notificationCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_notification")
        notificationCell.imageView?.image = BundleUtil.imageNamed("Notifications\(suffix)")
        
        chatCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_chat")
        chatCell.imageView?.image = BundleUtil.imageNamed("Chat\(suffix)")
        
        mediaCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_media")
        mediaCell.imageView?.image = BundleUtil.imageNamed("Media\(suffix)")
        
        storageManagementCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_storage_management")
        storageManagementCell.imageView?.image = BundleUtil.imageNamed("StorageManagement\(suffix)")
        
        feedbackCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_feedback")
        feedbackCell.imageView?.image = BundleUtil.imageNamed("DevMode\(suffix)")
        
        devModeCell.textLabel?.text = "Developer Settings"
        devModeCell.imageView?.image = BundleUtil.imageNamed("DevMode\(suffix)")
        
        passcodeLockCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_passcode_lock")
        passcodeLockCell.imageView?.image = BundleUtil.imageNamed("PasscodeLock\(suffix)")
        passcodeLockCell.accessibilityIdentifier = "SettingsPasscodeCell"

        threemaCallsCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_threema_calls")
        threemaCallsCell.imageView?.image = BundleUtil.imageNamed("ThreemaCallsSettings\(suffix)")
        
        threemaWebCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_threema_web")
        threemaWebCell.imageView?.image = BundleUtil.imageNamed("ThreemaWeb\(suffix)")
        
        multiDeviceCell.textLabel?.text = BundleUtil.localizedString(forKey: "multi_device_linked_devices_title")
        multiDeviceCell.imageView?.image = BundleUtil.imageNamed("ThreemaWeb\(suffix)")
        
        networkStatusCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_network_status")
        
        versionCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_version")
        
        usernameCellLabel.text = BundleUtil.localizedString(forKey: "settings_license_username")
        
        inviteAFriendCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_invite_a_friend")
        inviteAFriendCell.imageView?.image = BundleUtil.imageNamed("InviteAFriend\(suffix)")
        
        threemaChannelCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_threema_channel")
        threemaChannelCell.imageView?.image = BundleUtil.imageNamed("ThreemaChannel\(suffix)")
        
        threemaWorkCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_threema_work")
        threemaWorkCell.imageView?.image = BundleUtil.imageNamed("ThreemaWorkSettings\(suffix)")
        
        supportCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_support")
        supportCell.imageView?.image = BundleUtil.imageNamed("Support\(suffix)")
        
        privacyPolicyCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_privacy_policy")
        privacyPolicyCell.imageView?.image = BundleUtil.imageNamed("PrivacyPolicy\(suffix)")
        
        tosCell.textLabel?.text = BundleUtil.localizedString(forKey: "tos_cell_title")
        tosCell.imageView?.image = BundleUtil.imageNamed("TOS\(suffix)")
        
        licenseCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_license")
        licenseCell.imageView?.image = BundleUtil.imageNamed("License\(suffix)")
        
        advancedCell.textLabel?.text = BundleUtil.localizedString(forKey: "settings_advanced")
        advancedCell.imageView?.image = BundleUtil.imageNamed("Advanced\(suffix)")
    }
    
    private func updateConnectionStatus() {
        let stateName = ServerConnector.shared().name(for: ServerConnector.shared().connectionState)
        let locKey = "status_\(stateName)"
        
        var statusText = BundleUtil.localizedString(forKey: locKey)
        if ServerConnector.shared().isIPv6Connection == true {
            statusText = statusText.appending(" (IPv6)")
        }
        if ServerConnector.shared().isProxyConnection == true {
            statusText = statusText.appending(" (Proxy)")
        }
        
        networkStatusCell.detailTextLabel?.text = statusText
    }
    
    private func updatePasscodeLock() {
        if KKPasscodeLock.shared().isPasscodeRequired() == true {
            passcodeLockCell.detailTextLabel!.text = BundleUtil.localizedString(forKey: "On")
        }
        else {
            passcodeLockCell.detailTextLabel!.text = BundleUtil.localizedString(forKey: "Off")
        }
    }
    
    private func updateThreemaWeb() {
        if UserSettings.shared().threemaWeb == true {
            if WCSessionManager.shared.isRunningWCSession() == true {
                threemaWebCell.detailTextLabel?.text = BundleUtil.localizedString(forKey: "status_loggedIn")
            }
            else {
                threemaWebCell.detailTextLabel?.text = BundleUtil.localizedString(forKey: "On")
            }
        }
        else {
            threemaWebCell.detailTextLabel?.text = BundleUtil.localizedString(forKey: "Off")
        }
    }
    
    private func updateMultiDevice() {
        multiDeviceCell.detailTextLabel?.text = BundleUtil
            .localizedString(forKey: BusinessInjector().serverConnector.isMultiDeviceActivated ? "On" : "Off")
    }
    
    private func showConversation(for contact: ContactEntity) {
        let info = [
            kKeyContact: contact,
            kKeyForceCompose: NSNumber(booleanLiteral: true),
            kKeyText: "Version: \(ThreemaUtility.clientVersionWithMDM)",
        ] as [String: Any]
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: kNotificationShowConversation),
                object: nil,
                userInfo: info
            )
        }
    }
}

extension SettingsViewController {
    // MARK: DB observer
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if object as? ServerConnector == ServerConnector.shared(), keyPath == "running" {
            DispatchQueue.main.async {
                self.updateThreemaWeb()
            }
        }
    }
}

extension SettingsViewController {
    // MARK: Table view delegate
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Set header height to 0 to get the correct space
        if section == 0 {
            return 0.0
        }
        
        // Set header height to 0 to get the correct space
        if section == 1,
           ThreemaEnvironment.env() == .appStore {
            return 0.0
        }
        
        if LicenseStore.requiresLicenseKey() {
            if section == 4 {
                return 0.0
            }
        }
        
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        // Set footer height to 0 to get the correct space
        if section == 0 {
            if ThreemaEnvironment.env() == .appStore {
                return 0.0
            }
            else if ThreemaEnvironment.env() == .testFlight,
                    ThreemaApp.current == .onPrem {
                return 0.0
            }
        }
        
        if LicenseStore.requiresLicenseKey() {
            if section == 4 {
                return 0.0
            }
        }
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Remove dev and beta feedback cell if needed
        if section == 0 {
            let numberOfRows = super.tableView(tableView, numberOfRowsInSection: section)
            
            switch ThreemaEnvironment.env() {
            case .appStore:
                // Remove dev mode and beta feedback cells
                return 0
            case .testFlight:
                // Show dev mode and feedback when in red
                if ThreemaApp.current == .red || ThreemaApp.current == .workRed {
                    return numberOfRows
                }
                else if ThreemaApp.current == .onPrem {
                    return 0
                }
                // Remove dev mode cell in other versions
                return numberOfRows - 1
            case .xcode:
                return numberOfRows
            }
        }
        else if section == 2 {
            let numberOfRows = super.tableView(tableView, numberOfRowsInSection: section)

            // This should always be in sync with `disableMultiDeviceForVersionLessThan5()`
            
            switch ThreemaEnvironment.env() {
            case .appStore:
                // Remove multi device cells
                return numberOfRows - 1
            case .testFlight:
                // Show multi device only in consumer, red and work red betas
                if ThreemaApp.current == .threema || ThreemaApp.current == .red || ThreemaApp.current == .workRed {
                    return numberOfRows
                }
                else {
                    return numberOfRows - 1
                }
            case .xcode:
                // Always show multi device for debug builds
                return numberOfRows
            }
        }

        // hide Threema Channel for work
        if LicenseStore.requiresLicenseKey() {
            if section == 3 {
                return 3
            }
            if section == 4 {
                return 0
            }
        }
        else {
            if section == 3 {
                return 2
            }
        }
        
        return super.tableView(tableView, numberOfRowsInSection: section)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if LicenseStore.requiresLicenseKey() {
            if indexPath.section == 4 {
                return 0.0
            }
        }
        
        // For the target OnPrem are "Privacy Policy" and "Terms of Service" hidden
        if LicenseStore.isOnPrem(),
           indexPath.section == 5,
           indexPath.row == 1 || indexPath.row == 2 {
            return 0.0
        }
        
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        
        if cell.reuseIdentifier == "UsernameCell" {
            userNameCellDetailLabel.textColor = Colors.textLight
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1, indexPath.row == 6 {
            
            if KKPasscodeLock.shared().isPasscodeRequired() {
                lockScreen.presentLockScreenView(
                    viewController: self,
                    enteredCorrectly: {
                        let vc = KKPasscodeSettingsViewController(style: .grouped)
                        vc.delegate = self
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                )
            }
            else {
                let vc = KKPasscodeSettingsViewController(style: .grouped)
                vc.delegate = self
                navigationController?.pushViewController(vc, animated: true)
            }
        }
        else if indexPath.section == 0, indexPath.row == 0 {
            if let contact = BusinessInjector().entityManager.entityFetcher
                .contact(for: Constants.betaFeedbackIdentity) {
                showConversation(for: contact)
            }
            else {
                BusinessInjector().contactStore.addContact(
                    with: Constants.betaFeedbackIdentity,
                    verificationLevel: Int32(kVerificationLevelUnverified)
                ) { contact, _ in
                    guard let contact = contact else {
                        DDLogError("Can't add \(Constants.betaFeedbackIdentity) as contact")
                        return
                    }
                    
                    self.showConversation(for: contact)
                } onError: { error in
                    DDLogError("Can't add \(Constants.betaFeedbackIdentity) as contact \(error)")
                }
            }
        }
        else if indexPath.section == 0, indexPath.row == 1 {
            let vc = UIHostingController(rootView: DeveloperSettingsView())
            vc.navigationItem.largeTitleDisplayMode = .never
            navigationController?.pushViewController(vc, animated: true)
        }
        else if indexPath.section == 1, indexPath.row == 0 {
            let vc = UIHostingController(
                rootView: PrivacySettingsView(settingsVM: BusinessInjector().settingsStore as! SettingsStore)
            )
            vc.navigationItem.largeTitleDisplayMode = .never
            navigationController?.pushViewController(vc, animated: true)
        }
        else if indexPath.section == 1, indexPath.row == 2 {
            let vc = UIHostingController(rootView: NotificationSettingsView(
                settingsVM: BusinessInjector()
                    .settingsStore as! SettingsStore
            ))
            vc.navigationItem.largeTitleDisplayMode = .never
            navigationController?.pushViewController(vc, animated: true)
        }
        else if indexPath.section == 1, indexPath.row == 6 {
            let vc = KKPasscodeSettingsViewController(style: .grouped)
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)
        }
        else if indexPath.section == 1, indexPath.row == 5 {
            let vc = StorageManagementViewController()
            navigationController?.pushViewController(vc, animated: true)
        }
        else if indexPath.section == 4, indexPath.row == 0 {
            inviteController = InviteController()
            inviteController!.parentViewController = self
            inviteController!.shareViewController = self
            inviteController!.actionSheetViewController = self
            inviteController!.rect = tableView.rectForRow(at: indexPath)
            inviteController!.invite()
        }
        else if indexPath.section == 4, indexPath.row == 1 {
            AddThreemaChannelAction.run(in: self)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension SettingsViewController {
    // MARK: UIScrollViewDelegate
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let navHeight = navigationController!.navigationBar.frame.size.height
        let textInNavBar = navigationItem.prompt != nil
        if (navHeight <= BrandingUtils.compactNavBarHeight && !textInNavBar) ||
            (navHeight <= BrandingUtils.compactPromptNavBarHeight && textInNavBar),
            navigationItem.titleView != nil {
            navigationItem.titleView = nil
            title = BundleUtil.localizedString(forKey: "settings")
        }
        else if (navHeight > BrandingUtils.compactNavBarHeight && !textInNavBar) ||
            (navHeight > BrandingUtils.compactPromptNavBarHeight && textInNavBar),
            navigationItem.titleView == nil {
            BrandingUtils.updateTitleLogo(of: navigationItem, in: navigationController)
        }
    }
}

// MARK: - KKPasscodeSettingsViewControllerDelegate

extension SettingsViewController: KKPasscodeSettingsViewControllerDelegate {
    func didSettingsChanged(_ viewController: KKPasscodeSettingsViewController!) {
        updatePasscodeLock()
    }
}

// MARK: - ConnectionStateDelegate

extension SettingsViewController: ConnectionStateDelegate {
    func changed(connectionState state: ConnectionState) {
        DispatchQueue.main.async {
            self.updateConnectionStatus()
        }
    }
}
