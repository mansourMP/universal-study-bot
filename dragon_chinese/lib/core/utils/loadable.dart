sealed class Loadable<T> {
  const Loadable();
}

class Loading<T> extends Loadable<T> {
  const Loading();
}

class Data<T> extends Loadable<T> {
  final T value;
  const Data(this.value);
}

class ErrorState<T> extends Loadable<T> {
  final String message;
  final Object? error;
  const ErrorState(this.message, {this.error});
}
