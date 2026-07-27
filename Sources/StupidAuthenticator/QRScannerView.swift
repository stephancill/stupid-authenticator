@preconcurrency import AVFoundation
import SwiftUI

#if canImport(UIKit)

  struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
      let controller = ScannerViewController()
      controller.onScan = onScan
      controller.onCancel = onCancel
      return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
      uiViewController.onScan = onScan
      uiViewController.onCancel = onCancel
    }
  }

  final class ScannerViewController: UIViewController,
    @preconcurrency AVCaptureMetadataOutputObjectsDelegate
  {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .black
      addCancelButton()
      configureCamera()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      if !session.isRunning {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
          session.startRunning()
        }
      }
    }

    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      if session.isRunning {
        session.stopRunning()
      }
    }

    private func configureCamera() {
      guard let device = AVCaptureDevice.default(for: .video),
        let input = try? AVCaptureDeviceInput(device: device),
        session.canAddInput(input)
      else {
        showMessage("Camera unavailable")
        return
      }

      session.addInput(input)

      let output = AVCaptureMetadataOutput()
      guard session.canAddOutput(output) else {
        showMessage("QR scanning unavailable")
        return
      }

      session.addOutput(output)
      output.setMetadataObjectsDelegate(self, queue: .main)
      output.metadataObjectTypes = [.qr]

      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      layer.frame = view.bounds
      view.layer.addSublayer(layer)
      previewLayer = layer

      addInstructionLabel()
    }

    private func addCancelButton() {
      let cancelButton = UIButton(type: .system)
      cancelButton.translatesAutoresizingMaskIntoConstraints = false
      var configuration = UIButton.Configuration.filled()
      configuration.image = UIImage(systemName: "xmark")
      configuration.baseForegroundColor = .white
      configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 10, leading: 10, bottom: 10, trailing: 10)
      configuration.cornerStyle = .capsule
      cancelButton.configuration = configuration
      cancelButton.accessibilityLabel = "Cancel scanning"
      cancelButton.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
      view.addSubview(cancelButton)

      NSLayoutConstraint.activate([
        cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        cancelButton.widthAnchor.constraint(equalToConstant: 44),
        cancelButton.heightAnchor.constraint(equalToConstant: 44),
      ])
    }

    private func addInstructionLabel() {
      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.text = "Scan authenticator QR code"
      label.textColor = .white
      label.font = .preferredFont(forTextStyle: .headline)
      label.textAlignment = .center
      label.backgroundColor = UIColor.black.withAlphaComponent(0.45)
      label.layer.cornerRadius = 12
      label.clipsToBounds = true
      view.addSubview(label)

      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        label.bottomAnchor.constraint(
          equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        label.heightAnchor.constraint(equalToConstant: 48),
      ])
    }

    @objc private func cancelScanning() {
      session.stopRunning()
      onCancel?()
    }

    private func showMessage(_ message: String) {
      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.text = message
      label.textColor = .white
      label.textAlignment = .center
      view.addSubview(label)

      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
    }

    func metadataOutput(
      _ output: AVCaptureMetadataOutput,
      didOutput metadataObjects: [AVMetadataObject],
      from connection: AVCaptureConnection
    ) {
      guard !didScan,
        let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
        let value = object.stringValue
      else { return }

      didScan = true
      session.stopRunning()
      onScan?(value)
    }
  }
#endif
