%dnl This file will be recreated at the next build. To avoid this, delete this line.

%global requires %include %{_sourcedir}/requires.inc

%define appName tidi_assistant_flutter
%define orgName pro.tidi
%define appVersion 1.0.0+1

%define __strip /bin/true
%define debug_package %{nil}

%define _flutter_build_type Debug
%define _flutter_excludes ^lib(dconf|aurora_embedder|maliit-glib|xkbcommon|.+_platform_plugin)\\.so.*$
%define _flutter_psdk_version 5.2.1.200
%define _flutter_psdk_major 5