// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// The fork build's "Sync & update" window and notices. Kept apart from the
/// main catalogs so upstream string additions never collide with the fork's.
struct ForkSyncFeatureStrings {
    let title: String
    let forkBuild: String
    let stageFetch: String
    let stageRebase: String
    let stageVerify: String
    let stagePush: String
    let stageBuild: String
    let conflictTitle: String
    let conflictBody: String
    let resolveWithAI: String
    let retry: String
    let showLog: String
    let failedTitle: String
    let readyTitle: String
    let readyBody: String
    let restartToInstall: String
    let installing: String
    let installedTitle: String
    let installFailed: String
    let scriptMissing: String
    let close: String
    let cancel: String
}

extension FeatureStrings {
    static func forkSync(_ language: AppLanguage) -> ForkSyncFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

private extension ForkSyncFeatureStrings {
    static let enUS = ForkSyncFeatureStrings(
        title: "Sync with upstream",
        forkBuild: "Fork build",
        stageFetch: "Fetch upstream",
        stageRebase: "Rebase fork commits",
        stageVerify: "Run tests",
        stagePush: "Push to fork",
        stageBuild: "Build app",
        conflictTitle: "Rebase conflict",
        conflictBody: "The branch was left unchanged. Resolve the conflict, then retry.",
        resolveWithAI: "Resolve with AI",
        retry: "Retry",
        showLog: "Show log",
        failedTitle: "Sync stopped",
        readyTitle: "Build ready",
        readyBody: "Vorssaint quits, installs the new build and reopens.",
        restartToInstall: "Restart to install",
        installing: "Installing…",
        installedTitle: "Fork build installed",
        installFailed: "The build could not be installed. See the log.",
        scriptMissing: "The sync script is missing from the fork checkout.",
        close: "Close",
        cancel: "Cancel"
    )
    static let ptBR = ForkSyncFeatureStrings(
        title: "Sincronizar com upstream",
        forkBuild: "Build do fork",
        stageFetch: "Buscar upstream",
        stageRebase: "Rebase dos commits do fork",
        stageVerify: "Rodar testes",
        stagePush: "Enviar ao fork",
        stageBuild: "Compilar app",
        conflictTitle: "Conflito no rebase",
        conflictBody: "O branch ficou inalterado. Resolva o conflito e tente de novo.",
        resolveWithAI: "Resolver com IA",
        retry: "Tentar de novo",
        showLog: "Mostrar log",
        failedTitle: "Sincronização interrompida",
        readyTitle: "Build pronta",
        readyBody: "O Vorssaint fecha, instala a nova build e abre de novo.",
        restartToInstall: "Reiniciar para instalar",
        installing: "Instalando…",
        installedTitle: "Build do fork instalada",
        installFailed: "Não foi possível instalar a build. Veja o log.",
        scriptMissing: "O script de sincronização não está no checkout do fork.",
        close: "Fechar",
        cancel: "Cancelar"
    )
    static let tr = ForkSyncFeatureStrings(
        title: "Upstream ile eşitle",
        forkBuild: "Fork derlemesi",
        stageFetch: "Upstream’i getir",
        stageRebase: "Fork commit’lerini yeniden temellendir",
        stageVerify: "Testleri çalıştır",
        stagePush: "Fork’a gönder",
        stageBuild: "Uygulamayı derle",
        conflictTitle: "Rebase çakışması",
        conflictBody: "Dal değişmeden bırakıldı. Çakışmayı çözün, sonra tekrar deneyin.",
        resolveWithAI: "Yapay zekâ ile çöz",
        retry: "Tekrar dene",
        showLog: "Günlüğü göster",
        failedTitle: "Eşitleme durdu",
        readyTitle: "Derleme hazır",
        readyBody: "Vorssaint kapanır, yeni derlemeyi kurar ve yeniden açılır.",
        restartToInstall: "Kurmak için yeniden başlat",
        installing: "Kuruluyor…",
        installedTitle: "Fork derlemesi kuruldu",
        installFailed: "Derleme kurulamadı. Günlüğe bakın.",
        scriptMissing: "Eşitleme betiği fork kopyasında yok.",
        close: "Kapat",
        cancel: "Vazgeç"
    )
    static let ru = ForkSyncFeatureStrings(
        title: "Синхронизация с upstream",
        forkBuild: "Сборка форка",
        stageFetch: "Получить upstream",
        stageRebase: "Перенести коммиты форка",
        stageVerify: "Запустить тесты",
        stagePush: "Отправить в форк",
        stageBuild: "Собрать приложение",
        conflictTitle: "Конфликт при rebase",
        conflictBody: "Ветка не изменена. Разрешите конфликт и повторите.",
        resolveWithAI: "Решить с помощью ИИ",
        retry: "Повторить",
        showLog: "Показать журнал",
        failedTitle: "Синхронизация остановлена",
        readyTitle: "Сборка готова",
        readyBody: "Vorssaint закроется, установит новую сборку и откроется снова.",
        restartToInstall: "Перезапустить для установки",
        installing: "Установка…",
        installedTitle: "Сборка форка установлена",
        installFailed: "Не удалось установить сборку. См. журнал.",
        scriptMissing: "В копии форка нет скрипта синхронизации.",
        close: "Закрыть",
        cancel: "Отменить"
    )
    static let es = ForkSyncFeatureStrings(
        title: "Sincronizar con upstream",
        forkBuild: "Compilación del fork",
        stageFetch: "Obtener upstream",
        stageRebase: "Rebase de los commits del fork",
        stageVerify: "Ejecutar pruebas",
        stagePush: "Enviar al fork",
        stageBuild: "Compilar la app",
        conflictTitle: "Conflicto en el rebase",
        conflictBody: "La rama quedó sin cambios. Resuelve el conflicto y vuelve a intentarlo.",
        resolveWithAI: "Resolver con IA",
        retry: "Reintentar",
        showLog: "Mostrar registro",
        failedTitle: "Sincronización detenida",
        readyTitle: "Compilación lista",
        readyBody: "Vorssaint se cierra, instala la nueva compilación y se vuelve a abrir.",
        restartToInstall: "Reiniciar para instalar",
        installing: "Instalando…",
        installedTitle: "Compilación del fork instalada",
        installFailed: "No se pudo instalar la compilación. Consulta el registro.",
        scriptMissing: "Falta el script de sincronización en la copia del fork.",
        close: "Cerrar",
        cancel: "Cancelar"
    )
    static let sk = ForkSyncFeatureStrings(
        title: "Synchronizovať s upstream",
        forkBuild: "Zostava forku",
        stageFetch: "Stiahnuť upstream",
        stageRebase: "Presunúť commity forku",
        stageVerify: "Spustiť testy",
        stagePush: "Odoslať do forku",
        stageBuild: "Zostaviť aplikáciu",
        conflictTitle: "Konflikt pri rebase",
        conflictBody: "Vetva zostala nezmenená. Vyriešte konflikt a skúste to znova.",
        resolveWithAI: "Vyriešiť pomocou AI",
        retry: "Skúsiť znova",
        showLog: "Zobraziť záznam",
        failedTitle: "Synchronizácia sa zastavila",
        readyTitle: "Zostava je pripravená",
        readyBody: "Vorssaint sa ukončí, nainštaluje novú zostavu a znova sa otvorí.",
        restartToInstall: "Reštartovať a nainštalovať",
        installing: "Inštaluje sa…",
        installedTitle: "Zostava forku je nainštalovaná",
        installFailed: "Zostavu sa nepodarilo nainštalovať. Pozrite si záznam.",
        scriptMissing: "V kópii forku chýba skript synchronizácie.",
        close: "Zavrieť",
        cancel: "Zrušiť"
    )
    static let de = ForkSyncFeatureStrings(
        title: "Mit Upstream abgleichen",
        forkBuild: "Fork-Build",
        stageFetch: "Upstream abrufen",
        stageRebase: "Fork-Commits umsetzen",
        stageVerify: "Tests ausführen",
        stagePush: "Zum Fork pushen",
        stageBuild: "App bauen",
        conflictTitle: "Rebase-Konflikt",
        conflictBody: "Der Branch blieb unverändert. Konflikt lösen, dann erneut versuchen.",
        resolveWithAI: "Mit KI lösen",
        retry: "Erneut versuchen",
        showLog: "Protokoll zeigen",
        failedTitle: "Abgleich gestoppt",
        readyTitle: "Build bereit",
        readyBody: "Vorssaint wird beendet, installiert den neuen Build und öffnet sich wieder.",
        restartToInstall: "Neu starten und installieren",
        installing: "Wird installiert…",
        installedTitle: "Fork-Build installiert",
        installFailed: "Der Build konnte nicht installiert werden. Siehe Protokoll.",
        scriptMissing: "Das Abgleichskript fehlt im Fork-Checkout.",
        close: "Schließen",
        cancel: "Abbrechen"
    )
    static let fr = ForkSyncFeatureStrings(
        title: "Synchroniser avec upstream",
        forkBuild: "Build du fork",
        stageFetch: "Récupérer upstream",
        stageRebase: "Rebaser les commits du fork",
        stageVerify: "Lancer les tests",
        stagePush: "Pousser vers le fork",
        stageBuild: "Compiler l’app",
        conflictTitle: "Conflit de rebase",
        conflictBody: "La branche est restée inchangée. Résolvez le conflit, puis réessayez.",
        resolveWithAI: "Résoudre avec l’IA",
        retry: "Réessayer",
        showLog: "Afficher le journal",
        failedTitle: "Synchronisation arrêtée",
        readyTitle: "Build prêt",
        readyBody: "Vorssaint se ferme, installe le nouveau build et se rouvre.",
        restartToInstall: "Redémarrer pour installer",
        installing: "Installation…",
        installedTitle: "Build du fork installé",
        installFailed: "Impossible d’installer le build. Consultez le journal.",
        scriptMissing: "Le script de synchronisation est absent de la copie du fork.",
        close: "Fermer",
        cancel: "Annuler"
    )
    static let it = ForkSyncFeatureStrings(
        title: "Sincronizza con upstream",
        forkBuild: "Build del fork",
        stageFetch: "Recupera upstream",
        stageRebase: "Ribasa i commit del fork",
        stageVerify: "Esegui i test",
        stagePush: "Invia al fork",
        stageBuild: "Compila l’app",
        conflictTitle: "Conflitto nel rebase",
        conflictBody: "Il branch è rimasto invariato. Risolvi il conflitto, poi riprova.",
        resolveWithAI: "Risolvi con l’IA",
        retry: "Riprova",
        showLog: "Mostra log",
        failedTitle: "Sincronizzazione interrotta",
        readyTitle: "Build pronta",
        readyBody: "Vorssaint si chiude, installa la nuova build e si riapre.",
        restartToInstall: "Riavvia per installare",
        installing: "Installazione…",
        installedTitle: "Build del fork installata",
        installFailed: "Impossibile installare la build. Consulta il log.",
        scriptMissing: "Lo script di sincronizzazione manca nella copia del fork.",
        close: "Chiudi",
        cancel: "Annulla"
    )
    static let ja = ForkSyncFeatureStrings(
        title: "upstream と同期",
        forkBuild: "フォークのビルド",
        stageFetch: "upstream を取得",
        stageRebase: "フォークのコミットをリベース",
        stageVerify: "テストを実行",
        stagePush: "フォークにプッシュ",
        stageBuild: "アプリをビルド",
        conflictTitle: "リベースの競合",
        conflictBody: "ブランチは変更されていません。競合を解決してから再試行してください。",
        resolveWithAI: "AI で解決",
        retry: "再試行",
        showLog: "ログを表示",
        failedTitle: "同期を中止しました",
        readyTitle: "ビルド完了",
        readyBody: "Vorssaint を終了し、新しいビルドをインストールして再び開きます。",
        restartToInstall: "再起動してインストール",
        installing: "インストール中…",
        installedTitle: "フォークのビルドをインストールしました",
        installFailed: "ビルドをインストールできませんでした。ログを確認してください。",
        scriptMissing: "フォークのチェックアウトに同期スクリプトがありません。",
        close: "閉じる",
        cancel: "キャンセル"
    )
    static let ko = ForkSyncFeatureStrings(
        title: "upstream과 동기화",
        forkBuild: "포크 빌드",
        stageFetch: "upstream 가져오기",
        stageRebase: "포크 커밋 리베이스",
        stageVerify: "테스트 실행",
        stagePush: "포크에 푸시",
        stageBuild: "앱 빌드",
        conflictTitle: "리베이스 충돌",
        conflictBody: "브랜치는 변경되지 않았습니다. 충돌을 해결한 다음 다시 시도하세요.",
        resolveWithAI: "AI로 해결",
        retry: "다시 시도",
        showLog: "로그 보기",
        failedTitle: "동기화가 중단됨",
        readyTitle: "빌드 준비됨",
        readyBody: "Vorssaint가 종료되고 새 빌드를 설치한 뒤 다시 열립니다.",
        restartToInstall: "재시작하여 설치",
        installing: "설치 중…",
        installedTitle: "포크 빌드가 설치됨",
        installFailed: "빌드를 설치할 수 없습니다. 로그를 확인하세요.",
        scriptMissing: "포크 체크아웃에 동기화 스크립트가 없습니다.",
        close: "닫기",
        cancel: "취소"
    )
    static let uk = ForkSyncFeatureStrings(
        title: "Синхронізувати з upstream",
        forkBuild: "Збірка форку",
        stageFetch: "Отримати upstream",
        stageRebase: "Перенести коміти форку",
        stageVerify: "Запустити тести",
        stagePush: "Надіслати у форк",
        stageBuild: "Зібрати застосунок",
        conflictTitle: "Конфлікт під час rebase",
        conflictBody: "Гілку не змінено. Розвʼяжіть конфлікт і повторіть.",
        resolveWithAI: "Розвʼязати з ШІ",
        retry: "Повторити",
        showLog: "Показати журнал",
        failedTitle: "Синхронізацію зупинено",
        readyTitle: "Збірка готова",
        readyBody: "Vorssaint закриється, встановить нову збірку й відкриється знову.",
        restartToInstall: "Перезапустити для встановлення",
        installing: "Встановлення…",
        installedTitle: "Збірку форку встановлено",
        installFailed: "Не вдалося встановити збірку. Перегляньте журнал.",
        scriptMissing: "У копії форку немає скрипту синхронізації.",
        close: "Закрити",
        cancel: "Скасувати"
    )
    static let zhHans = ForkSyncFeatureStrings(
        title: "与上游同步",
        forkBuild: "Fork 构建",
        stageFetch: "获取上游",
        stageRebase: "变基 fork 的提交",
        stageVerify: "运行测试",
        stagePush: "推送到 fork",
        stageBuild: "构建应用",
        conflictTitle: "变基冲突",
        conflictBody: "分支保持不变。解决冲突后重试。",
        resolveWithAI: "用 AI 解决",
        retry: "重试",
        showLog: "显示日志",
        failedTitle: "同步已停止",
        readyTitle: "构建完成",
        readyBody: "Vorssaint 将退出、安装新构建并重新打开。",
        restartToInstall: "重新启动以安装",
        installing: "正在安装…",
        installedTitle: "已安装 fork 构建",
        installFailed: "无法安装构建。请查看日志。",
        scriptMissing: "fork 的检出目录中缺少同步脚本。",
        close: "关闭",
        cancel: "取消"
    )
    static let zhTW = ForkSyncFeatureStrings(
        title: "與上游同步",
        forkBuild: "Fork 版本",
        stageFetch: "取得上游",
        stageRebase: "重新定基 fork 的提交",
        stageVerify: "執行測試",
        stagePush: "推送到 fork",
        stageBuild: "建置 App",
        conflictTitle: "重新定基衝突",
        conflictBody: "分支維持不變。解決衝突後再重試。",
        resolveWithAI: "用 AI 解決",
        retry: "重試",
        showLog: "顯示記錄",
        failedTitle: "同步已停止",
        readyTitle: "建置完成",
        readyBody: "Vorssaint 會結束、安裝新版本並重新開啟。",
        restartToInstall: "重新啟動以安裝",
        installing: "正在安裝…",
        installedTitle: "已安裝 fork 版本",
        installFailed: "無法安裝此版本，請查看記錄。",
        scriptMissing: "fork 的工作目錄中找不到同步腳本。",
        close: "關閉",
        cancel: "取消"
    )
    static let zhHK = ForkSyncFeatureStrings(
        title: "與上游同步",
        forkBuild: "Fork 版本",
        stageFetch: "取得上游",
        stageRebase: "重新定基 fork 的提交",
        stageVerify: "執行測試",
        stagePush: "推送到 fork",
        stageBuild: "建置 App",
        conflictTitle: "重新定基衝突",
        conflictBody: "分支維持不變。解決衝突後再重試。",
        resolveWithAI: "用 AI 解決",
        retry: "重試",
        showLog: "顯示記錄",
        failedTitle: "同步已停止",
        readyTitle: "建置完成",
        readyBody: "Vorssaint 會結束、安裝新版本並重新開啟。",
        restartToInstall: "重新啟動以安裝",
        installing: "正在安裝…",
        installedTitle: "已安裝 fork 版本",
        installFailed: "無法安裝此版本，請查看記錄。",
        scriptMissing: "fork 的工作目錄中找不到同步腳本。",
        close: "關閉",
        cancel: "取消"
    )
}
