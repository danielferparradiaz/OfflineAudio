/*
 * ytdlp_stub.c — Launcher Android que embe el CPython oficial de python.org
 * (embeddable package para Android) y ejecuta `yt-dlp` exactamente igual que
 * `python3 -m yt_dlp`.
 *
 * Layout esperado junto a este ejecutable (producido por build_ytdlp_runtime.sh):
 *   <dir>/ytdlp                     <- este binario
 *   <dir>/prefix/lib/python3.14/            (stdlib)
 *   <dir>/prefix/lib/python3.14/lib-dynload/*.so
 *   <dir>/prefix/lib/python3.14/site-packages/yt_dlp/**
 *   <dir>/prefix/lib/libpython3.14.so (+ libcrypto/ssl/sqlite *_python.so)
 *
 * El runtime se descarga dentro del bin dir de la app desde Ajustes > Paquetes
 * del motor (o la URL personalizada binary.ytdlp_url). LD_LIBRARY_PATH lo
 * prepara el motor (pipeline/process) apuntando a <dir>/prefix/lib.
 */

#include <Python.h>

#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Viene de -DPY_VER="3.14" en build_ytdlp_runtime.sh (derivado de
 * PYTHON_VERSION en runtime_versions.env). Default solo para compilación suelta. */
#ifndef PY_VER
#define PY_VER "3.14"
#endif
static const char *PY_VER_STR = PY_VER;

/* Directorio en el que vive este ejecutable (/proc/self/exe -> dirname). */
static char *self_dir(char *buf, size_t size) {
    ssize_t n = readlink("/proc/self/exe", buf, size - 1);
    if (n <= 0) return NULL;
    buf[n] = '\0';
    char *slash = strrchr(buf, '/');
    if (slash == NULL) {
        strncpy(buf, ".", size - 1);
        buf[size - 1] = '\0';
    } else if (slash == buf) {
        buf[1] = '\0';
    } else {
        *slash = '\0';
    }
    return buf;
}

static int build_config(PyConfig *config, int argc, char **argv, char *prefix, size_t prefix_size) {
    PyStatus st;
    char exe[PATH_MAX];
    char libdir[PATH_MAX];
    char libdyn[PATH_MAX];
    char sitedir[PATH_MAX];

    if (self_dir(exe, sizeof(exe)) == NULL) {
        fprintf(stderr, "ytdlp: cannot resolve own directory\n");
        return -1;
    }
    snprintf(prefix, prefix_size, "%s/prefix", exe);
    snprintf(libdir, sizeof(libdir), "%s/lib/python%s", prefix, PY_VER_STR);
    snprintf(libdyn, sizeof(libdyn), "%s/lib-dynload", libdir);
    snprintf(sitedir, sizeof(sitedir), "%s/site-packages", libdir);

    PyConfig_InitPythonConfig(config);

    st = PyConfig_SetBytesString(config, &config->program_name, argv[0]);
    if (PyStatus_Exception(st)) return -1;

    st = PyConfig_SetBytesArgv(config, argc, argv);
    if (PyStatus_Exception(st)) return -1;
    config->parse_argv = 0;

    st = PyConfig_SetBytesString(config, &config->home, prefix);
    if (PyStatus_Exception(st)) return -1;

    config->module_search_paths_set = 1;
    if (PyStatus_Exception(PyWideStringList_Append(&config->module_search_paths, Py_DecodeLocale(libdir, NULL)))) return -1;
    if (PyStatus_Exception(PyWideStringList_Append(&config->module_search_paths, Py_DecodeLocale(libdyn, NULL)))) return -1;
    if (PyStatus_Exception(PyWideStringList_Append(&config->module_search_paths, Py_DecodeLocale(sitedir, NULL)))) return -1;
    return 0;
}

static int run_ytdlp(void) {
    int rc = 1;
    PyObject *runpy = NULL;
    PyObject *run_module = NULL;
    PyObject *args = NULL;
    PyObject *kwargs = NULL;
    PyObject *res = NULL;

    runpy = PyImport_ImportModule("runpy");
    if (runpy == NULL) goto done;
    run_module = PyObject_GetAttrString(runpy, "run_module");
    if (run_module == NULL) goto done;

    args = Py_BuildValue("(s)", "yt_dlp");
    if (args == NULL) goto done;
    kwargs = Py_BuildValue("{s:s}", "run_name", "__main__");
    if (kwargs == NULL) goto done;

    res = PyObject_Call(run_module, args, kwargs);
    if (res != NULL) {
        rc = 0;
        goto done;
    }

    /* yt-dlp termina con sys.exit(status); en modo embebido eso llega como
     * SystemExit y hay que traducirlo al exit code del proceso. */
    if (PyErr_ExceptionMatches(PyExc_SystemExit)) {
        PyObject *type = NULL, *value = NULL, *tb = NULL;
        long code = 1;
        int have_code = 0;
        PyErr_Fetch(&type, &value, &tb);
        PyErr_NormalizeException(&type, &value, &tb);
        if (value != NULL) {
            PyObject *code_obj = PyObject_GetAttrString(value, "code");
            if (code_obj != NULL) {
                if (code_obj == Py_None) {
                    code = 0;
                    have_code = 1;
                } else if (PyLong_Check(code_obj)) {
                    code = PyLong_AsLong(code_obj);
                    have_code = 1;
                }
                Py_DECREF(code_obj);
            }
        }
        Py_XDECREF(type);
        Py_XDECREF(value);
        Py_XDECREF(tb);
        if (have_code) rc = (int)code;
        goto done;
    }

    PyErr_Print(); /* otro error: mostramos el traceback */
    rc = 1;

done:
    Py_XDECREF(res);
    Py_XDECREF(kwargs);
    Py_XDECREF(args);
    Py_XDECREF(run_module);
    Py_XDECREF(runpy);
    return rc;
}

int main(int argc, char **argv) {
    PyConfig config;
    char prefix[PATH_MAX];

    if (argc < 1) return 2;

    PyConfig_InitPythonConfig(&config);
    if (build_config(&config, argc, argv, prefix, sizeof(prefix)) != 0) {
        PyConfig_Clear(&config);
        PyErr_Print();
        return 2;
    }

    PyStatus st = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(st)) {
        Py_ExitStatusException(st);
        return 2; /* unreachable */
    }

    (void)prefix;
    int rc = run_ytdlp();

    if (Py_FinalizeEx() < 0) {
        rc = 120; /* igual que CPython cuando falla el finalize */
    }
    return rc;
}