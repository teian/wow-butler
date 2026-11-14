#include <stdio.h>
#include <unistd.h>

#include "my_application.h"

int main(int argc, char** argv) {
  int status;
  {
    g_autoptr(MyApplication) app = my_application_new();
    status = g_application_run(G_APPLICATION(app), argc, argv);
  }
  // The app and its engine are shut down at this point. Leaving through
  // exit() would run the libraries' atexit handlers, and the NVIDIA EGL
  // driver's handler crashes (SIGSEGV in libnvidia-eglcore) once GTK has
  // released the display. Nothing left needs those handlers, so flush the
  // standard streams and end the process directly.
  fflush(nullptr);
  _exit(status);
}
