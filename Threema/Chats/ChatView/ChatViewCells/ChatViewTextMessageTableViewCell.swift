//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022 Threema GmbH
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

import ThreemaFramework
import UIKit

/// Display a text message
final class ChatViewTextMessageTableViewCell: ChatViewBaseTableViewCell, MeasurableCell {
    static var sizingCell = ChatViewTextMessageTableViewCell()
    
    /// Text message to display
    ///
    /// Reset it when the message had any changes to update data shown in the views (e.g. date or status symbol).
    var textMessageAndNeighbors: (message: TextMessage, neighbors: ChatViewDataSource.MessageNeighbors)? {
        didSet {
            updateCell(for: textMessageAndNeighbors?.message)
            
            super.setMessage(to: textMessageAndNeighbors?.message, with: textMessageAndNeighbors?.neighbors)
        }
    }
    
    override var shouldShowDateAndState: Bool {
        didSet {
            messageDateAndStateView.isHidden = !shouldShowDateAndState
            
            guard oldValue != shouldShowDateAndState else {
                return
            }
            
            // The length of the rendered text in the message might be shorter than `messageDateAndStateView`.
            // Thus we fully remove it to avoid having it set the width of the message bubble.
            if messageDateAndStateView.isHidden {
                contentStack.removeArrangedSubview(messageDateAndStateView)
            }
            else {
                contentStack.addArrangedSubview(messageDateAndStateView)
            }
        }
    }
    
    // MARK: - Views
    
    private lazy var messageQuoteStackView: MessageQuoteStackView = {
        let view = MessageQuoteStackView()
        
        let tapInteraction = UITapGestureRecognizer(target: self, action: #selector(quoteViewTapped))
        tapInteraction.delegate = self
        view.addGestureRecognizer(tapInteraction)
        
        return view
    }()
    
    private lazy var messageQuoteStackViewConstraints = [
        messageQuoteStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
        messageQuoteStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        messageQuoteStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
    ]
    
    private lazy var messageTextView = MessageTextView(messageTextViewDelegate: self)
    private lazy var messageDateAndStateView = MessageDateAndStateView()
    
    private lazy var contentStack = DefaultMessageContentStackView(arrangedSubviews: [
        messageTextView,
        messageDateAndStateView,
    ])
    
    private lazy var contentStackViewConstraints: [NSLayoutConstraint] = {
        [
            contentStack.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ]
        
    }()
    
    private lazy var contentStackViewWithQuoteConstraints: [NSLayoutConstraint] = {
        [
            contentStack.topAnchor.constraint(
                equalTo: messageQuoteStackView.bottomAnchor,
                constant: ChatViewConfiguration.Quote.quoteTextCellDistance
            ),
            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ]

    }()
    
    private lazy var containerView: UIView = {
        let view = UIView()
        
        // This adds the margin to the chat bubble border
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: -ChatViewConfiguration.Content.defaultTopBottomInset,
            leading: -ChatViewConfiguration.Content.defaultLeadingTrailingInset,
            bottom: -ChatViewConfiguration.Content.defaultTopBottomInset,
            trailing: -ChatViewConfiguration.Content.defaultLeadingTrailingInset
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()

    // MARK: - Configuration
    
    override func configureCell() {
        super.configureCell()
        
        containerView.addSubview(messageQuoteStackView)
        messageQuoteStackView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate(messageQuoteStackViewConstraints)
        NSLayoutConstraint.activate(contentStackViewWithQuoteConstraints)
   
        super.addContent(rootView: containerView)
    }
    
    // MARK: - Updates
    
    override func updateColors() {
        super.updateColors()
        
        messageQuoteStackView.updateColors()
        messageTextView.updateColors()
        messageDateAndStateView.updateColors()
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        containerView.isUserInteractionEnabled = !editing
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        if chatViewTableViewCellDelegate?.currentSearchText != nil {
            if selected {
                updateCell(for: textMessageAndNeighbors?.message)
            }
        }
    }
    
    private func updateCell(for textMessage: TextMessage?) {
       
        // Quote stack view displaying / hiding
        if textMessage?.quoteMessage != nil {
            containerView.addSubview(messageQuoteStackView)
            NSLayoutConstraint.deactivate(contentStackViewConstraints)
            NSLayoutConstraint.activate(messageQuoteStackViewConstraints)
            NSLayoutConstraint.activate(contentStackViewWithQuoteConstraints)
        }
        else {
            messageQuoteStackView.removeFromSuperview()
            NSLayoutConstraint.deactivate(messageQuoteStackViewConstraints)
            NSLayoutConstraint.deactivate(contentStackViewWithQuoteConstraints)
            NSLayoutConstraint.activate(contentStackViewConstraints)
        }
        
        messageQuoteStackView.quoteMessage = textMessage?.quoteMessage
        messageTextView.text = textMessage?.text ?? ""
        messageDateAndStateView.message = textMessage

        updateAccessibility()
    }
    
    private func updateAccessibility() {
        guard textMessageAndNeighbors?.message.quoteMessage != nil else {
            return
        }
        
        // TODO: IOS-3119 construct accessibility label for different types
        accessibilityHint = BundleUtil.localizedString(forKey: "quote_interaction_hint")
    }
    
    // MARK: - Action Functions
    
    @objc func quoteViewTapped() {
        guard let quotedMessageID = textMessageAndNeighbors?.message.quotedMessageID else {
            return
        }
        chatViewTableViewCellDelegate?.quoteTapped(on: quotedMessageID)
    }
}

// MARK: - MessageTextViewDelegate

extension ChatViewTextMessageTableViewCell: MessageTextViewDelegate {
    func showContact(identity: String) {
        chatViewTableViewCellDelegate?.show(identity: identity)
    }
    
    func didSelectText(in textView: MessageTextView?) {
        chatViewTableViewCellDelegate?.didSelectText(in: textView)
    }
}

// MARK: - Reusable

extension ChatViewTextMessageTableViewCell: Reusable { }

// MARK: - ContextMenuAction

extension ChatViewTextMessageTableViewCell: ContextMenuAction {
    
    func buildContextMenu(at indexPath: IndexPath) -> UIContextMenuConfiguration? {
       
        guard let message = textMessageAndNeighbors?.message else {
            return nil
        }

        typealias Provider = ChatViewContextMenuActionProvider
        var menuItems = [UIAction]()
        
        // Copy
        let copyHandler = {
            UIPasteboard.general.string = message.text
            NotificationPresenterWrapper.shared.present(type: .copySuccess)
        }
        
        // Share
        let shareItems = [message.text as Any]
        
        // Quote
        let quoteHandler = {
            guard let chatViewTableViewCellDelegate = self.chatViewTableViewCellDelegate else {
                return
            }
            
            chatViewTableViewCellDelegate.showQuoteView(message: message)
        }
        
        // Details
        let detailsHandler = {
            self.chatViewTableViewCellDelegate?.showDetails(for: message.objectID)
        }
        
        // Edit
        let editHandler = {
            self.chatViewTableViewCellDelegate?.startMultiselect()
        }
        
        let defaultActions = Provider.defaultActions(
            message: message,
            speakText: message.text,
            shareItems: shareItems,
            activityViewAnchor: contentView,
            copyHandler: copyHandler,
            quoteHandler: quoteHandler,
            detailsHandler: detailsHandler,
            editHandler: editHandler
        )
        
        menuItems.append(contentsOf: defaultActions)
        
        // Build menu
        let menu = UIMenu(children: menuItems)
        
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
            menu
        }
    }
}
