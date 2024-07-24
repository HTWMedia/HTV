class GithubRelease {
  /// tag名称
  late final String tagName;

  /// 下载url
  late final String downloadUrl;

  /// release说明
  late final String description;

  GithubRelease({
    required this.tagName,
    required this.downloadUrl,
    required this.description,
  });

  @override
  String toString() {
    return 'GithubRelease{tagName: $tagName, downloadUrl: $downloadUrl, description: $description}';
  }
}
