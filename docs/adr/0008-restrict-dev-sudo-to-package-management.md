---
status: "accepted"
date: 2026-08-26
decision-makers: [Uragami Taichi]
consulted: []
informed: []
---

# `dev`のsudoはOSパッケージ管理コマンドのみに限定する

## 背景と課題

[ADR-0004](0004-network-isolation-in-container-owner-match.md) は、`dev`ユーザーが無制限のパスワードレスsudoを持つこと（spec User Story 19）を前提として受け入れ、「サンドボックス内からの意図的な脱出は防御対象外であり、防ぎたいのは誤操作や意図しない副作用である」という線引きをした。同ADRはその上で「rootは隔離できない。`dev`はsudo経由でルールを削除できる」ことを弱点として明記している。

改めて`dev`の無制限sudoの必要性を洗い出したところ、次の事実が判明した。

* `apply_network_isolation`（`bin/cc-sandbox`）は、`dev`のsudoを経由せず、ホスト側から`docker exec -u root`で隔離ルールを適用している。隔離の**適用**は`dev`の権限に依存していない。
* cc-sandbox自身のランタイム自動化（`ensure_playwright_browser`、docker CLIの`DOCKER_HOST=tcp://dind:2375`経由の利用）は、いずれも`dev`のsudoに依存していない。ランタイムで`dev`のsudoが使われるとすれば、それは人間またはClaude Code（bypassPermissionsモード）によるアドホックな操作に限られる。
* `dev`にはパスワードが設定されていない（`useradd`に`-p`なし）。sudoersのNOPASSWD対象を絞れば、対象外のコマンドはパスワードを提示しようがなく事実上完全に到達不能になる。

一方で、bypassPermissionsモードの日常運用でsudoを要する場面は「OSパッケージの追加インストール」以外にほぼ想起できない。mise/uv/npmはユーザー領域にインストールするためroot不要であり、Dockerも[DinDサイドカー](0001-dind-sidecar-privileged.md)経由でroot不要である。

無制限sudoを残すことで最も実害が大きいのは、悪意ではなく**利便性**により、`dev`（＝Claude Code含む）が`sudo iptables -F`等でネットワーク隔離を意図せず無効化してしまう経路である。ADR-0004自身が「誤操作や意図しない副作用」を防御対象と定義しているにもかかわらず、その防御対象の中で最も影響が大きい操作（自分自身の隔離を外すこと）だけが無防備なまま残っていた。

## 決定

**`dev`のsudoを`apt-get`/`apt`（OSパッケージの追加インストール）のみに限定する。** sudoersの`NOPASSWD:ALL`を、コマンドを明示列挙する形に置き換える。

これにより、`sudo iptables`・`sudo bash`・`sudo su`等、リストにない操作は`dev`に設定されたパスワードが存在しないため実行不能になる。隔離ルールの適用（`docker exec -u root`によるホスト側からの操作）には影響しない。

`apt-get`のpostinstフックはroot権限で任意コード実行が可能であり、「rootを完全に奪えない」ことまでは保証しない。この残存リスクは許容する。今回の主眼は「ネットワーク隔離の意図しない無効化を防ぐこと」であり、rootの完全な排除ではない。

### 結果として生じること

* 良い点: ネットワーク隔離を`dev`（Claude Code含む）が誤って/安易に無効化する経路が塞がる。ADR-0004が定義する「誤操作や意図しない副作用の防止」という防御対象に、この経路も含まれるようになる。
* 良い点: cc-sandbox自身の挙動には影響しない（隔離の適用・ランタイム自動化のいずれも`dev`のsudoに依存していないため）。
* 悪い点: `apt-get install`のpostinstフックを介したroot権限の奪取は引き続き可能。ADR-0004が明記した「意図的な脱出は防御対象外」という基本方針そのものは変わっていない。
* 悪い点: これまで無条件にsudoが使えることを前提にしていた運用（想定外のOSレベル操作が必要になった場合）は、都度このADRを見直してsudoersに追加する対応が必要になる。

## 再検討のトリガー

* `apt-get`/`apt`以外にrootが必要な操作が日常的に発生するようになったとき（許可リストへの追加を検討する）
* 防ぎたい対象が「誤操作」から「意図的な脱出」へ変わったとき（ADR-0004と同じトリガー。その場合はallowlist化では不十分で、より強い隔離方式の検討が必要になる）

## 補足情報

* [ADR-0004](0004-network-isolation-in-container-owner-match.md) を部分的に上書きする。ADR-0004が受け入れた「サンドボックス内からの意図的な脱出は防御対象外」という基本方針は変えていない。変わったのは、ADR-0004自身が定義する防御対象（誤操作・意図しない副作用）の範囲内で、隔離無効化という具体的な経路への対応を追加した点のみ。
* 実装: `sandbox/Dockerfile`のsudoers設定、`test/basic_up_down.bats`。
