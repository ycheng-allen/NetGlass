import SwiftUI

struct ClaudeAccountPolicyView: View {
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("账号停用依据与自查", systemImage: "checklist").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("官方资料 · 需自行核对").font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            Text("账号层面的违规无法从 IP 判断。下面列出官方规则；未读取或检测你的账号、对话、付款及登录凭据。")
                .font(.system(size: 11)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("遇到验证弹窗时如何区分") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("网络／人机验证：可检查出口、DNS、UDP 和时区差异，但验证提示本身不能证明账号已被停用。", systemImage: "network.badge.shield.half.filled")
                    Label("证件／Persona 核验：官方说明部分功能可能要求身份或业务验证。这与网络检测不同，应通过产品内入口核对官方说明。", systemImage: "person.text.rectangle")
                    Text("没有公开资料能把某个 IP 分数、机房属性或一次验证弹窗换算成封号概率；本工具也无法检测你的账号验证状态。")
                    Link("官方身份验证说明", destination: URL(string: "https://support.claude.com/en/articles/14328960-identity-verification-on-claude")!)
                    Link("第三方排查参考 · Net.Coffee", destination: URL(string: "https://ip.net.coffee/claude/identity.html")!)
                }.font(.system(size: 11)).foregroundStyle(palette.sub).padding(.top, 10)
            }.font(.system(size: 11))
            DisclosureGroup("查看 \(ClaudeAccountPolicy.items.count) 项官方规则") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ClaudeAccountPolicy.items) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top) {
                                Text(item.title).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("待自查 · 未检测").font(.system(size: 9)).foregroundStyle(palette.sub)
                            }
                            Text(item.detail).font(.system(size: 11)).foregroundStyle(palette.sub)
                                .fixedSize(horizontal: false, vertical: true)
                            if let url = URL(string: item.sourceURL) {
                                Link(item.sourceTitle, destination: url).font(.system(size: 10))
                            }
                        }
                        if item.id != ClaudeAccountPolicy.items.last?.id { Divider() }
                    }
                    Text("资料核对：\(ClaudeAccountPolicy.reviewedOn)；条款与地区政策可能更新，请查看当前版本和生效日期。")
                        .font(.system(size: 10)).foregroundStyle(palette.sub)
                    Link("官方申诉与复核说明", destination: URL(string: ClaudeAccountPolicy.appealsURL)!)
                        .font(.system(size: 11))
                }.padding(.top, 12)
            }.font(.system(size: 11))
        }.padding(20).foregroundStyle(palette.text)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }
}
