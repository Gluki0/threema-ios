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

import UIKit

/// Label with correct font and color for metadata text
final class MessageMetadataTextLabel: UILabel {

    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLabel()
        updateColors()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLabel()
        updateColors()
    }
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    private func configureLabel() {
        numberOfLines = 0
        
        font = ChatViewConfiguration.MessageMetadata.font
        adjustsFontForContentSizeCategory = true
        
        lineBreakMode = .byWordWrapping
    }
    
    // MARK: - Update
    
    func updateColors() {
        Colors.setTextColor(Colors.textLight, label: self)
    }
}