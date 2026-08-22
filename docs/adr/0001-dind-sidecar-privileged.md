# DinDサイドカーは特権コンテナ方式で実装する

サンドボックス内でTestcontainersやPostgreSQL/Redis等のサービスコンテナを動かすため、ネストしたDocker環境が必要になる。sysboxやrootless Dockerのような非特権方式は隔離が強い一方、macOS側（Docker Desktop/OrbStackのVM上のLinuxカーネル）で安定動作するか不透明なため、まずは `docker:dind` を特権コンテナのサイドカーとして動かす方式を採用する。「特権コンテナ」はサンドボックスという境界の内側に閉じているため、ホストへの実害という観点では許容範囲と判断した。

## Considered Options

- sysbox / rootless Docker（非特権でのネスト） — 隔離は強いが、macOS環境での動作検証コストが高く見送った
- ホストのDockerソケットを直接マウント — ホストのDockerデーモンにフルアクセスできてしまい隔離が実質破綻するため却下
