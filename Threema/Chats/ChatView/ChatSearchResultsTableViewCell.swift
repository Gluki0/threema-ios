//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2023 Threema GmbH
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
import UIKit

/// Cell to show a search results
final class ChatSearchResultsTableViewCell: ThemedCodeStackTableViewCell {
    
    /// Message to show in this cell
    var message: BaseMessage? {
        didSet {
            updateCel(for: message)
        }
    }
    
    // MARK: - Private properties
    
    private let debug = false
    
    private lazy var markupParser = MarkupParser()

    // MARK: - Views
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()

        label.font = UIFont.preferredFont(forTextStyle: ChatViewConfiguration.SearchResults.nameTextStyle)
        
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if debug {
            label.backgroundColor = .systemBlue
        }
        
        return label
    }()
    
    private lazy var dateLabel: UILabel = {
        let label = UILabel()
        
        label.font = UIFont.preferredFont(forTextStyle: ChatViewConfiguration.SearchResults.metadataTextStyle)
        
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        if debug {
            label.backgroundColor = .systemRed
        }
        
        return label
    }()
    
    private lazy var disclosureIndicatorImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: ChatViewConfiguration.SearchResults.metadataTextStyle
        )
                
        return imageView
    }()
    
    private lazy var dateAndDisclosureIndicatorContainerView: UIView = {
        let view = UIView(frame: .zero)
        
        view.addSubview(dateLabel)
        view.addSubview(disclosureIndicatorImageView)
        
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        disclosureIndicatorImageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            view.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
            view.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),
            
            dateLabel.firstBaselineAnchor.constraint(equalTo: disclosureIndicatorImageView.firstBaselineAnchor),
            dateLabel.trailingAnchor.constraint(
                equalTo: disclosureIndicatorImageView.leadingAnchor,
                constant: -ChatViewConfiguration.SearchResults.metadataSpacing
            ),
            disclosureIndicatorImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        return view
    }()
    
    private lazy var topLineStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            nameLabel,
            dateAndDisclosureIndicatorContainerView,
        ])
       
        stack.axis = .horizontal
        stack.spacing = ChatViewConfiguration.SearchResults.nameAndMetadataSpacing
        stack.alignment = .firstBaseline
        stack.distribution = .equalSpacing
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            stack.axis = .vertical
            stack.alignment = .leading
            
            disclosureIndicatorImageView.isHidden = true
            accessoryType = .disclosureIndicator
        }
        
        if debug {
            stack.backgroundColor = .systemMint
        }
        
        return stack
    }()
    
    private lazy var messagePreviewTextLabel: UILabel = {
        let label = UILabel()
        
        label.numberOfLines = 2
        
        label.font = UIFont.preferredFont(forTextStyle: ChatViewConfiguration.SearchResults.messagePreviewTextTextStyle)
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            label.numberOfLines = 3
        }
        
        if debug {
            label.backgroundColor = .systemPink
        }
        
        return label
    }()
    
    override func configureCell() {
        super.configureCell()
        
        contentStack.axis = .vertical
        contentStack.spacing = ChatViewConfiguration.SearchResults.verticalSpacing
        contentStack.alignment = .fill
        
        contentStack.addArrangedSubview(topLineStack)
        contentStack.addArrangedSubview(messagePreviewTextLabel)
        
        if debug {
            contentStack.backgroundColor = .systemCyan
        }
    }
    
    // MARK: - Updates
    
    override func updateColors() {
        super.updateColors()
        
        Colors.setTextColor(Colors.text, label: nameLabel)
        Colors.setTextColor(Colors.textLight, label: dateLabel)
        disclosureIndicatorImageView.tintColor = Colors.textLight
        
        Colors.setTextColor(Colors.textLight, label: messagePreviewTextLabel)
    }
    
    private func updateCel(for message: BaseMessage?) {
        guard let message = message else {
            nameLabel.text = nil
            dateLabel.text = nil
            messagePreviewTextLabel.text = nil
            return
        }
        
        nameLabel.text = message.localizedSenderName
        dateLabel.text = DateFormatter.relativeTimeTodayAndMediumDateOtherwise(for: message.sectionDate)
        
        // TODO: (IOS-2906) Replace this by a generic preview string for all messages
        // For now we only search text messages, ballot titles and file names (see `-[EntityFetcher messagesContaining:inConversation:]`)
        switch message {
        case let textMessage as TextMessage:
            messagePreviewTextLabel.text = markupParser.previewString(for: textMessage.text)
        case let ballotMessage as BallotMessage:
            messagePreviewTextLabel.text = ballotMessage.ballot.title
            
        case let fileMessageEntity as FileMessageEntity:
            messagePreviewTextLabel.text = fileMessageEntity.fileName
            
        default:
            messagePreviewTextLabel.text = nil
            DDLogError("Unknown message type in chat search results")
        }
    }
}

// MARK: - Reusable

extension ChatSearchResultsTableViewCell: Reusable { }