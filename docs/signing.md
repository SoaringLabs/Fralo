# Developer ID 签名与 Apple 公证

用于维护者制作直接分发的 DMG，不会推送 GitHub 或创建 Release。
源码自行构建默认使用 ad-hoc 签名；正式发布需要有效的 Developer ID Application
证书及对应私钥。拖拽安装的 DMG 不需要 Developer ID Installer 证书。

## 准备凭据

在 Apple Developer 后台签发 Developer ID Application（G2）证书，并导入生成 CSR
的同一台 Mac 的钥匙串。检查可用身份：

    security find-identity -v -p codesigning

为公证配置钥匙串凭据。在自己的终端运行下面的交互命令，按提示输入
Apple 账号、Team ID 和 App 专用密码（或选择 App Store Connect API 密钥）：

    xcrun notarytool store-credentials fralo-notary

凭据不写入源码或构建命令；不要提交私钥、.p12、.p8 或专用密码。
公证上传的是构建产物，用户的截图不参与这个流程。

## 构建与签名

把下面的占位符换成上一步列出的 Developer ID Application 证书 SHA-1：

    .venv/bin/python scripts/package.py --dmg --sign "CERTIFICATE_SHA1"

脚本先签名 Sparkle 更新助手和框架、内置 CLI，再签名 App，使用 Hardened Runtime 和安全时间戳；
随后制作并签名 DMG。dist/fralo 与 App 内置 CLI 保持一致。
不能使用 Apple Development 或 Apple Distribution 证书代替 Developer ID Application。

## 公证与恢复

    mkdir -p artifacts/signing
    xcrun notarytool submit dist/Fralo-0.1.0-arm64.dmg \
      --keychain-profile fralo-notary --output-format json \
      > artifacts/signing/submission.json

保存返回的 submission ID，后续用同一个 ID 查询，不要因为等待超时重复提交：

    xcrun notarytool info SUBMISSION_ID --keychain-profile fralo-notary
    xcrun notarytool log SUBMISSION_ID --keychain-profile fralo-notary \
      artifacts/signing/notary-log.json

只有状态为 Accepted 时才继续。将凭证附到最终分发的 DMG 后，重新生成校验文件：

    xcrun stapler staple dist/Fralo-0.1.0-arm64.dmg
    (cd dist && shasum -a 256 Fralo-0.1.0-arm64.dmg > SHA256SUMS.txt)
    .venv/bin/python scripts/verify_package.py --require-notarized

验证脚本要求：App、CLI 和 DMG 使用同一团队的 Developer ID；可执行文件启用
Hardened Runtime 和安全时间戳；DMG 公证凭证有效；App 与 DMG 均获 Gatekeeper 接受。
最终用户分发容器为已附公证凭证的 DMG。不要把未附凭证的 App 另行打成 ZIP 分发。

公证后不要改动 App 内容或重建 DMG；变更后必须重新签名、公证并生成校验值。
最终 DMG 可按 [更新分发说明](updates.md)生成 `appcast.xml`，之后仍不允许修改 DMG。
浏览器真实下载后的首次安装与启动仍需要单独验收。

参考：[Apple 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)、
[公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。
