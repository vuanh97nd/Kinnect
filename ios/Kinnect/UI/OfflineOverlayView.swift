import UIKit

final class OfflineOverlayView: UIView {
    var onRetry: (() -> Void)?

    private let container = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        container.layer.cornerRadius = 24
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.06
        container.layer.shadowOffset = CGSize(width: 0, height: 8)
        container.layer.shadowRadius = 24
        addSubview(container)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Đang kết nối lại Kinnect"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0)
        titleLabel.textAlignment = .center

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "Kiểm tra kết nối Wi-Fi hoặc dữ liệu di động của bạn rồi thử lại."
        messageLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = UIColor(red: 0.42, green: 0.43, blue: 0.48, alpha: 1.0)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Thử lại ngay", for: .normal)
        retryButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = UIColor(red: 0.43, green: 0.29, blue: 1.0, alpha: 1.0)
        retryButton.layer.cornerRadius = 14
        retryButton.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)

        container.addSubview(titleLabel)
        container.addSubview(messageLabel)
        container.addSubview(retryButton)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            retryButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            retryButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            retryButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            retryButton.heightAnchor.constraint(equalToConstant: 48),
            retryButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -28)
        ])
    }

    @objc private func handleRetry() {
        onRetry?()
    }
}
