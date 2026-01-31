/*
Copyright (C) 2025 NoneBot

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, see <https://www.gnu.org/licenses/>.
*/

#include <Python.h>
#include <chrono>
#include <fontconfig/fontconfig.h>
#include <litehtml.h>
#include <litehtml/render_item.h>
#include <thread>
#include <utility>

#include "cairo_wrapper.h"
#include "container_info.h"
#include "debug_container.h"
#include "font_wrapper.h"

extern "C" {
static PyObject* render(PyObject* mod, PyObject* args) {
    PyObject *exception_fn = nullptr, *asyncio_run_coroutine_threadsafe = nullptr,
             *urljoin = nullptr, *asyncio_loop = nullptr, *img_fetch_fn = nullptr,
             *css_fetch_fn = nullptr;
    const char *font_name, *lang, *culture, *html_content, *base_url;
    float arg_dpi, arg_width, arg_height, default_font_size;
    int fast_data_scheme, allow_refit, debug_flag,
        image_flag; // image_flag: -1 for PNG, 0-100 for JPEG quality
    container_info info;
    if (!PyArg_ParseTuple(args, "ssffffspissOOOOOOpp", &html_content, &base_url,
                          &arg_dpi, &arg_width, &arg_height, &default_font_size,
                          &font_name, &allow_refit, &image_flag, &lang, &culture,
                          &exception_fn, &asyncio_run_coroutine_threadsafe, &urljoin,
                          &asyncio_loop, &img_fetch_fn, &css_fetch_fn,
                          &fast_data_scheme, &debug_flag)) {
        return nullptr;
    }
    Py_INCREF(args);
    info.dpi = arg_dpi;
    info.width = arg_width;
    info.height = arg_height;
    info.default_font_size_pt = default_font_size;
    info.default_font_name = std::string(font_name);
    info.language = std::string(lang);
    info.culture = std::string(culture);
    info.font_options = cairo_font_options_create();
    info.native_data_scheme = fast_data_scheme;
    std::string html_content_str(html_content), base_url_str(base_url);
    cairo_font_options_set_antialias(info.font_options, CAIRO_ANTIALIAS_DEFAULT);
    cairo_font_options_set_hint_style(info.font_options, CAIRO_HINT_STYLE_NONE);
    cairo_font_options_set_subpixel_order(info.font_options,
                                          CAIRO_SUBPIXEL_ORDER_DEFAULT);

    if (asyncio_loop == nullptr) {
        PyErr_SetString(PyExc_TypeError, "Invalid asyncio event loop");
        return nullptr;
    }

    PyObject* future = PyObject_CallMethod(asyncio_loop, "create_future", nullptr);
    if (future == nullptr) {
        PyErr_SetString(PyExc_RuntimeError, "Failed to create future from event loop");
        return nullptr;
    }

    std::thread([=]() {
        PangoFontMap* font_map =
            pango_cairo_font_map_new_for_font_type(CAIRO_FONT_TYPE_FT);
        pango_cairo_font_map_set_default(PANGO_CAIRO_FONT_MAP(font_map));

        auto bail = [=]() {
            GILState bail_gil;
            PyObjectPtr exc_ty(nullptr), exc_val(nullptr), exc_tb(nullptr);
            PyErr_Fetch(&exc_ty.ptr, &exc_val.ptr, &exc_tb.ptr);
            PyErr_NormalizeException(&exc_ty.ptr, &exc_val.ptr, &exc_tb.ptr);
            if (exc_tb != nullptr) {
                PyException_SetTraceback(exc_val.ptr, exc_tb.ptr);
            }
            PyObjectPtr set_exception(PyObject_GetAttrString(future, "set_exception"));
            if (set_exception == nullptr) {
                PyErr_Restore(exc_ty.ptr, exc_val.ptr, exc_tb.ptr);
                PyErr_Print();
            } else if (PyObject_CallMethod(asyncio_loop, "call_soon_threadsafe", "OO",
                                           set_exception.ptr, exc_val.ptr) == nullptr) {
                PyErr_Restore(exc_ty.ptr, exc_val.ptr, exc_tb.ptr);
                PyErr_Print();
            }
            Py_DECREF(future);
            Py_DECREF(args);
            g_object_unref(font_map);
        };

        debug_container container(base_url_str, info);
        container.urljoin = urljoin;
        container.asyncio_run_coroutine_threadsafe = asyncio_run_coroutine_threadsafe;
        container.m_loop = asyncio_loop;
        container.m_img_fetch_fn = img_fetch_fn;
        container.exception_logger = exception_fn;
        container.m_css_fetch_fn = css_fetch_fn;
        auto doc = litehtml::document::createFromString(
            html_content_str, &container, litehtml::master_css,
            " html { background-color: #fff; }");
        int width = arg_width;
        litehtml::pixel_t best_width = doc->render(arg_width);
        if (allow_refit && best_width < arg_width) {
            width = best_width;
            doc->render(width);
        }
        int content_height = doc->height();
        if (width < 1 || content_height < 1) {
            width = std::max(1, width);
            content_height = std::max(1, content_height);
            GILState gil;
            PyErr_WarnEx(PyExc_RuntimeWarning,
                         "Resulting image has zero width or height", 1);
        }
        cairo_surface_t* surface =
            cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, content_height);
        cairo_surface_t* dbg_surface =
            debug_flag
                ? cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, content_height)
                : nullptr;
        container.set_debug_surface(dbg_surface);
        if (!surface) {
            GILState surface_creation_failed_gil;
            PyErr_SetString(PyExc_RuntimeError, "Could not create surface");
            return bail();
        }
        if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
            GILState surface_status_error_gil;
            const char* err_msg = cairo_status_to_string(cairo_surface_status(surface));
            PyErr_SetString(PyExc_RuntimeError, err_msg);
            cairo_surface_destroy(surface);
            cairo_surface_destroy(dbg_surface);
            return bail();
        }
        auto cr = cairo_create(surface);

        // Fill background with white color
        cairo_save(cr);
        cairo_rectangle(cr, 0, 0, width, content_height);
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0);
        cairo_fill(cr);
        cairo_restore(cr);

        // Draw document
        litehtml::position clip(0, 0, width, content_height);

        doc->draw((litehtml::uint_ptr)cr, 0, 0, &clip);

        cairo_surface_flush(surface);
        cairo_destroy(cr);

        GILState gil;
        PyObjectPtr bytes_obj(nullptr);
        if (image_flag >= 0 && image_flag <= 100) {
            unsigned char* jpeg_data = nullptr;
            size_t jpeg_size = 0;
            cairo_status_t stat;
            Py_BEGIN_ALLOW_THREADS stat =
                cairo_wrapper::cairo_surface_write_to_jpeg_mem(surface, &jpeg_data,
                                                               &jpeg_size, image_flag);
            cairo_surface_destroy(surface);
            cairo_surface_destroy(dbg_surface);
            Py_END_ALLOW_THREADS;

            if (stat != CAIRO_STATUS_SUCCESS) {
                const char* err_msg = cairo_status_to_string(stat);
                PyErr_SetString(PyExc_RuntimeError, err_msg);
                return bail();
            }
            bytes_obj.ptr = PyBytes_FromStringAndSize(
                reinterpret_cast<const char*>(jpeg_data), jpeg_size);
            free(jpeg_data);
        } else {
            std::vector<unsigned char> bytes;
            cairo_status_t stat;
            Py_BEGIN_ALLOW_THREADS stat = cairo_surface_write_to_png_stream(
                surface, cairo_wrapper::write_to_vector, &bytes);
            cairo_surface_destroy(surface);
            cairo_surface_destroy(dbg_surface);
            Py_END_ALLOW_THREADS;

            if (stat != CAIRO_STATUS_SUCCESS) {
                const char* err_msg = cairo_status_to_string(stat);
                PyErr_SetString(PyExc_RuntimeError, err_msg);
                return bail();
            }
            bytes_obj.ptr = PyBytes_FromStringAndSize(
                reinterpret_cast<const char*>(bytes.data()), bytes.size());
        }

        if (bytes_obj == nullptr) {
            return bail();
        }
        PyObjectPtr set_result(PyObject_GetAttrString(future, "set_result"));
        if (set_result == nullptr) {
            return bail();
        }

        PyObjectPtr result_obj(nullptr);
        if (debug_flag) {
            std::string debug_html = container.export_debug_layers();
            PyObjectPtr html_obj(
                PyUnicode_FromStringAndSize(debug_html.c_str(), debug_html.size()));
            if (html_obj == nullptr) {
                return bail();
            }
            result_obj.ptr = PyTuple_Pack(2, bytes_obj.ptr, html_obj.ptr);
        } else {
            Py_INCREF(bytes_obj.ptr);
            result_obj = bytes_obj;
        }
        PyObjectPtr call_soon_result(
            PyObject_CallMethod(asyncio_loop, "call_soon_threadsafe", "OO",
                                set_result.ptr, result_obj.ptr));
        if (call_soon_result == nullptr) {
            return bail();
        }
        Py_DECREF(future);
        Py_DECREF(args);
        g_object_unref(font_map);
    }).detach();
    return future;
}

static PyObject* setup_fontconfig(PyObject* mod, PyObject* args) {
    init_fontconfig();
    Py_RETURN_NONE;
}

static PyMethodDef methods[] = {
    {/* .ml_name = */ "_render_internal",
     /*.ml_meth = */ render,
     /*.ml_flags = */ METH_VARARGS,
     /*.ml_doc = */ "Core function for rendering HTML page."},
    {/* .ml_name = */ "_init_fontconfig_internal",
     /*.ml_meth = */ setup_fontconfig,
     /*.ml_flags = */ METH_VARARGS,
     /*.ml_doc = */ "Setup fontconfig if not already initialized."},
    {nullptr, nullptr, 0, nullptr},
};

static struct PyModuleDef_Slot module_slots[] = {
#if (defined(Py_LIMITED_API) ? Py_LIMITED_API : PY_VERSION_HEX) >=                     \
    0x030C0000 // Python 3.12+
    {Py_mod_multiple_interpreters, Py_MOD_PER_INTERPRETER_GIL_SUPPORTED},
#endif
#if (defined(Py_LIMITED_API) ? Py_LIMITED_API : PY_VERSION_HEX) >=                     \
    0x030D0000 // Python 3.13+
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},
#endif
    {0, NULL},
};

static struct PyModuleDef core_module = {
    /*.m_base = */ PyModuleDef_HEAD_INIT,
    /*.m_name = */ "core",
    /*.m_doc = */ "Native core of htmlkit, built with litehtml.",
    /*.m_size = */ 0, // fontconfig is global
    /*.m_methods = */ methods,
    /*.m_slots = */ module_slots,
};

PyMODINIT_FUNC PyInit_core(void) { return PyModuleDef_Init(&core_module); }
}
