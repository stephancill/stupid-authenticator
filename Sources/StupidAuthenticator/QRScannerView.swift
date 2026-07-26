@preconcurrency import AVFoundation
import SwiftUI

struct QRScannerView: UIViewControllerRepresentable {
  let onScan: (String) -> Void

  func makeUIViewController(context: Context) -> ScannerViewController {
    let controller = ScannerViewController()
    controller.onScan = onScan
    return controller
  }

  func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController,
  @preconcurrency AVCaptureMetadataOutputObjectsDelegate
{
  var onScan: ((String) -> Void)?

  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var didScan = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
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

    addOverlay()
  }

  private func addOverlay() {
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
      label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
      label.heightAnchor.constraint(equalToConstant: 48),
    ])
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
