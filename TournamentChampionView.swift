//
//  Untitled.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/26/26.
import SwiftUI
import UIKit

struct TournamentChampionView: View {
    let champion: PlayerStanding
    let podium: [PlayerStanding] // Expected order: [2nd, 1st, 3rd]
    let onDone: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isPresented = false
    
    // Exact 1:1 translation of RN spring: stiffness 220, damping 26, mass 1
    private let appleSpring = Animation.interpolatingSpring(stiffness: 220, damping: 26)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ZStack {
            // Pure system background. No cards, no borders, no gradients.
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 8) {
                    // Overline
                    Text("TOURNAMENT COMPLETE")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.secondary)
                    
                    // Champion Name (Largest text on screen)
                    Text(champion.name)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                        .tracking(-1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    // Computed Line
                    Text("\(champion.wins) wins · \(champion.pointDifferential > 0 ? "+" : "")\(champion.pointDifferential) diff")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(-0.2)
                        .monospacedDigit()
                }
                .padding(.bottom, 56)
                
                // Elegant Podium (2nd, 1st, 3rd)
                HStack(alignment: .bottom, spacing: 18) {
                    if podium.count >= 1 {
                        podiumItem(place: 2, player: podium[0], height: 72, isChampion: false)
                    } else {
                        Spacer().frame(width: 60, height: 72)
                    }
                    
                    if podium.count >= 2 {
                        podiumItem(place: 1, player: podium[1], height: 96, isChampion: true)
                    } else {
                        Spacer().frame(width: 60, height: 96)
                    }
                    
                    if podium.count >= 3 {
                        podiumItem(place: 3, player: podium[2], height: 64, isChampion: false)
                    } else {
                        Spacer().frame(width: 60, height: 64)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Single Primary Action: Done
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        // Motion Rules: Gentle scale 0.96 -> 1.0 + opacity 0 -> 1
        .scaleEffect(isPresented ? 1.0 : 0.96)
        .opacity(isPresented ? 1.0 : 0.0)
        .animation(
            UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.28) : appleSpring,
            value: isPresented
        )
        .onAppear {
            // One heavy haptic the moment the screen appears
            heavyHaptic.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isPresented = true
            }
        }
    }
    
    // MARK: - Podium Item
    
    private func podiumItem(place: Int, player: PlayerStanding, height: CGFloat, isChampion: Bool) -> some View {
        VStack(spacing: 12) {
            // Podium Block
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isChampion ? Color.primary : Color.secondary.opacity(0.2))
                .frame(height: height)
                .overlay(
                    Text("\(place)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        // Invert color for 1st place so it's visible on the solid block
                        .foregroundColor(isChampion ? (Color(UIColor.systemBackground) == .black ? .black : .white) : .secondary)
                )
            
            // Name
            Text(player.name)
                .font(.system(size: 15, weight: isChampion ? .semibold : .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Record
            Text("\(player.wins)W")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scale Button Style (Subtle 0.97 press)
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.interpolatingSpring(stiffness: 400, damping: 15), value: configuration.isPressed)
    }
}

