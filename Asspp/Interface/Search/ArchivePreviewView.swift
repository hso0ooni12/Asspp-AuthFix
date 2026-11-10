//
//  ArchivePreviewView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct ArchivePreviewView: View {
    let archive: AppStore.AppPackage
    var preferredIconSize: CGFloat?
    var lineLimit: Int? = 1
    var showsVersion = true
    var showsRating = false
    var storefront: String?

    private var iconSize: CGFloat {
        preferredIconSize ?? 50
    }

    private var screenScale: CGFloat {
        #if canImport(UIKit)
            UIScreen.main.scale
        #else
            NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            KFImage(URL(string: archive.software.artworkUrl))
                // Downsample the 512x512 artwork to the cell size instead of
                // decoding it at full resolution for a ~50pt icon.
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: iconSize, height: iconSize)))
                .scaleFactor(screenScale)
                // Cache only the decoded thumbnail. Keeping every original
                // artwork in memory slows scrolling through long search lists.
                .antialiased(true)
                .resizable()
                .clipShape(.rect(cornerRadius: 0.2184466 * iconSize))
                .frame(width: iconSize, height: iconSize, alignment: .center)
                .overlay {
                    RoundedRectangle(cornerRadius: 0.2184466 * iconSize)
                        .strokeBorder(AssppTheme.separator.opacity(0.35), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(archive.software.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if showsVersion {
                    Text(archive.software.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(archive.software.sellerName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if showsRating || storefront != nil {
                    HStack(spacing: 8) {
                        if showsRating, archive.software.userRatingCount > 0 {
                            Label(String(format: "%.1f", archive.software.averageUserRating),
                                  systemImage: "star.fill")
                        }
                        if let storefront {
                            Text(storefront).monospaced()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
