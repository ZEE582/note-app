import Foundation
import AVFoundation
import SwiftUI

import PencilKit
import UIKit

// MARK: - Audio

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileName: String?

    func start() {
        guard !isRecording else { return }
        permissionDenied = false
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            permissionDenied = true
            return
        }

        let name = "\(UUID().uuidString).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            permissionDenied = true
            return
        }
        self.recorder = recorder
        fileName = name
        duration = 0
        recorder.record()
        isRecording = true

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so hopping through
            // MainActor.assumeIsolated keeps the published state consistent
            // without scheduling a task on every tick.
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.duration = self.recorder?.currentTime ?? 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        duration = recorder?.currentTime ?? duration
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - PencilKit

struct DrawingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var data: Data?
    var inkColor: Color = .indigo
    var penWidth: CGFloat = 4
    var onChange: () -> Void = { }

    var body: some View {
        NavigationStack {
            PencilCanvas(data: $data, inkColor: inkColor, penWidth: penWidth, onChange: onChange)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("الرسم")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إلغاء") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("تم") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

struct PencilCanvas: UIViewRepresentable {
    @Binding var data: Data?
    var inkColor: Color
    var penWidth: CGFloat
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(data: $data, onChange: onChange)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .systemBackground
        canvas.isOpaque = true
        canvas.delegate = context.coordinator
        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        applyTool(to: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        applyTool(to: canvas)
    }

    private func applyTool(to canvas: PKCanvasView) {
        let tool = PKInkingTool(.pen, color: UIColor(inkColor), width: penWidth)
        if canvas.tool as AnyObject !== tool {
            canvas.tool = tool
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var data: Binding<Data?>
        var onChange: () -> Void

        init(data: Binding<Data?>, onChange: @escaping () -> Void) {
            self.data = data
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Persist the strokes immediately so dismissing the sheet without
            // another edit never loses the drawing.
            data.wrappedValue = try? canvasView.drawing.dataRepresentation()
            onChange()
        }
    }
}
