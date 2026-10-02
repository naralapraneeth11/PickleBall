//
//  FormChartView.swift
//  PickleBall
//
//  The scrubbable form line. Drag across it and the hero number and date
//  follow your finger, with a haptic tick on every match.
//

import SwiftUI
import Charts
import CourtKit

struct FormChartView: View {
    let points: [FormPoint]
    let accent: Color
    @Binding var selection: Int?

    private var values: [Double] { points.map(\.value) }

    private var domain: ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        let pad = max(4, (high - low) * 0.25)
        return max(0, low - pad)...min(100, high + pad)
    }

    var body: some View {
        Chart {
            ForEach(points.indices, id: \.self) { index in
                AreaMark(
                    x: .value("Match", index),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Form", points[index].value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                )

                LineMark(
                    x: .value("Match", index),
                    y: .value("Form", points[index].value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            if let selected = clampedSelection {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Court.text.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Match", selected),
                    y: .value("Form", points[selected].value)
                )
                .foregroundStyle(accent)
                .symbolSize(90)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...max(1, points.count - 1))
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: clampedSelection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Form over your last \(points.count) matches")
        .accessibilityValue(points.last.map { String(format: "%.1f", $0.value) } ?? "No matches")
    }

    private var clampedSelection: Int? {
        guard let selection, !points.isEmpty else { return nil }
        return min(max(selection, 0), points.count - 1)
    }
}

/// Tiny win/loss form line for list rows.
struct FormSparkline: View {
    /// Oldest → newest. `true` = win.
    let results: [Bool]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let series = cumulative
            let low = series.min() ?? 0
            let high = series.max() ?? 1
            let span = max(1, high - low)
            Path { path in
                for (index, value) in series.enumerated() {
                    let x = series.count > 1 ? geo.size.width * CGFloat(index) / CGFloat(series.count - 1) : geo.size.width / 2
                    let y = geo.size.height * (1 - CGFloat(value - low) / CGFloat(span))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(trendUp ? accent : Court.text.opacity(0.45), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private var cumulative: [Int] {
        var running = 0
        return [0] + results.map { won in
            running += won ? 1 : -1
            return running
        }
    }

    private var trendUp: Bool { (cumulative.last ?? 0) >= 0 }
}
