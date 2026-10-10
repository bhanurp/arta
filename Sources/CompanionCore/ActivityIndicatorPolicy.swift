public enum ActivityIndicatorPolicy {
  public static func isVisible(working: Bool, hovering: Bool, notificationsVisible: Bool) -> Bool {
    working && !hovering && !notificationsVisible
  }
}
