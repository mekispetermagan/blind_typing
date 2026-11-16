enum UserRole { admin, trainer, student }

enum AppArea { admin, trainer, student }

List<AppArea> areasForRole(UserRole role) => switch (role) {
  UserRole.admin => [AppArea.admin, AppArea.trainer, AppArea.student],
  UserRole.trainer => [AppArea.trainer, AppArea.student],
  UserRole.student => [AppArea.student],
};

AppArea? initialAreaForRole(UserRole role) =>
    role == UserRole.student ? AppArea.student : null;
