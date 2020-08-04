include(CMakeParseArguments)


# Add google tests macro
macro(ADD_GOOGLE_TESTS executable)
  if(MSVC)
    # QT-Separation-Move
    file(TO_NATIVE_PATH "${QT_INSTALL_DIR}/bin/" QT_BIN_PATH) # DLM:
    file(TO_NATIVE_PATH "${OPENSSL_ROOT_DIR}/bin/" OPENSSL_BIN_PATH)
    string(REGEX REPLACE "([^\\]);" "\\1\\\\;" CURRENT_ENV "$ENV{PATH}")
    set(NEWPATH "${QT_BIN_PATH};${OPENSSL_BIN_PATH};${CURRENT_ENV}")
  else()
    set(NEWPATH $ENV{PATH})
  endif()

  foreach(source ${ARGN})
    if(NOT "${source}" MATCHES "/moc_.*cxx")
      string(REGEX MATCH .*cpp source "${source}")
      if(source)
        file(READ "${source}" contents)
        string(REGEX MATCHALL "TEST_?F?\\(([A-Za-z_0-9 ,]+)\\)" found_tests ${contents})
        foreach(hit ${found_tests})
          string(REGEX REPLACE ".*\\(([A-Za-z_0-9]+)[, ]*([A-Za-z_0-9]+)\\).*" "\\1.\\2" test_name ${hit})
          add_test(${test_name} "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${executable}" --gtest_filter=${test_name})
          set_tests_properties(${test_name} PROPERTIES TIMEOUT 660 ENVIRONMENT "PATH=${NEWPATH}")
        endforeach()
      endif()
    endif()
  endforeach()
endmacro()

# Create source groups automatically based on file path
macro(CREATE_SRC_GROUPS SRC)
  foreach(F ${SRC})
    string(REGEX MATCH "(^.*)([/\\].*$)" M ${F})
    if(CMAKE_MATCH_1)
      string(REGEX REPLACE "[/\\]" "\\\\" DIR ${CMAKE_MATCH_1})
      source_group(${DIR} FILES ${F})
    else()
      source_group(\\ FILES ${F})
    endif()
  endforeach()
endmacro()

# Create test targets
macro(CREATE_TEST_TARGETS BASE_NAME SRC DEPENDENCIES)
  if(BUILD_TESTING)
    add_executable(${BASE_NAME}_tests ${SRC})

    list(APPEND ALL_TESTING_TARGETS "${BASE_NAME}_tests")
    set(ALL_TESTING_TARGETS "${ALL_TESTING_TARGETS}" PARENT_SCOPE)


    CREATE_SRC_GROUPS("${SRC}")

    set(ALL_DEPENDENCIES ${DEPENDENCIES})

    target_link_libraries(${BASE_NAME}_tests
      CONAN_PKG::gtest
      ${ALL_DEPENDENCIES}
    )

    ADD_GOOGLE_TESTS(${BASE_NAME}_tests ${SRC})
    if(TARGET "${BASE_NAME}_resources")
      add_dependencies("${BASE_NAME}_tests" "${BASE_NAME}_resources")
    endif()

    ## suppress deprecated warnings in unit tests
    if(UNIX)
      set_target_properties(${ALL_TESTING_TARGETS} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
    elseif(MSVC)
      set_target_properties(${ALL_TESTING_TARGETS} PROPERTIES COMPILE_FLAGS "/wd4996")
    endif()

  endif()
endmacro()


macro(MAKE_LITE_SQL_TARGET IN_FILE BASE_FILE)
  set(cmake_script "
    file(READ \"${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cpp\" text)
    string(REPLACE ${BASE_FILE}.hpp ${BASE_FILE}.hxx modified_text \"\${text}\")
    file(WRITE \"${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cxx\" \"\${modified_text}\")
  ")
  file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}fix.cmake" ${cmake_script})
  add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hxx" "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cxx"
    COMMAND "${LITESQL_GEN_EXE}" --output-dir="${CMAKE_CURRENT_BINARY_DIR}" --target=c++ "${CMAKE_CURRENT_SOURCE_DIR}/${IN_FILE}"
    COMMAND "${CMAKE_COMMAND}" -E rename "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hpp" "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hxx"
    COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}fix.cmake"
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cpp"
    DEPENDS litesql-gen "${CMAKE_CURRENT_SOURCE_DIR}/${IN_FILE}"
  )
endmacro()


# add a swig target
# KEY_I_FILE should include path, see src/utilities/CMakeLists.txt.
macro(MAKE_SWIG_TARGET NAME SIMPLENAME KEY_I_FILE I_FILES PARENT_TARGET PARENT_SWIG_TARGETS)
  set(SWIG_DEFINES "")
  set(SWIG_COMMON "")

  ##
  ## Begin collection of requirements to reduce SWIG regenerations
  ## and fix parallel build issues
  ##

  # Get all of the source files for the parent target this SWIG library is wrapping
  get_target_property(target_files ${PARENT_TARGET} SOURCES)

  foreach(f ${target_files})
    # Get the extension of the source file
    get_source_file_property(p "${f}" LOCATION)
    get_filename_component(extension "${p}" EXT)

    # If it's a header file ("*.h*") add it to the list of headers
    if("${extension}" MATCHES "\\.h.*")
      if("${extension}" MATCHES "\\..xx" OR "${p}" MATCHES "ui_.*\\.h")
        list(APPEND GeneratedHeaders "${p}")
      else()
        list(APPEND RequiredHeaders "${p}")
      endif()
    endif()
  endforeach()

  set(Prereq_Dirs
      "${QT_LIBRARY_DIR}" # QT-Separation-Move
      "${PROJECT_BINARY_DIR}/Products/"
      "${PROJECT_BINARY_DIR}/Products/Release"
      "${PROJECT_BINARY_DIR}/Products/Debug"
      "${LIBRARY_SEARCH_DIRECTORY}"
  )


  # Now, append all of the .i* files provided to the macro to the
  # list of required headers.
  foreach(i ${I_FILES})
    get_source_file_property(p "${i}" LOCATION)
    get_filename_component(extension "${p}" EXT)
    if("${extension}" MATCHES "\\..xx")
      list(APPEND GeneratedHeaders "${p}")
    else()
      list(APPEND RequiredHeaders "${p}")
    endif()
  endforeach()

  # RequiredHeaders now represents all of the headers and .i files that all
  # of the SWIG targets generated by this macro call rely on.
  # And GeneratedHeaders contains all .ixx and .hxx files needed to make
  # these SWIG targets

  set(ParentSWIGWrappers "")
  # Now we loop through all of the parent swig targets and collect the requirements from them
  foreach(p ${PARENT_SWIG_TARGETS})
    get_target_property(target_files "ruby_${p}" SOURCES)

    if("${target_files}" STREQUAL "target_files-NOTFOUND")
      message(FATAL_ERROR "Unable to locate sources for ruby_${p}, there is probably an error in the build order for ${NAME} in the top level CMakeLists.txt or you have not properly specified the dependencies in MAKE_SWIG_TARGET for ${NAME}")
    endif()

    #message(STATUS "${target_files}")
    # This is the real data collection
    list(APPEND ParentSWIGWrappers ${${p}_SWIG_Depends})
  endforeach()


  # Reduce the size of the RequiredHeaders list
  list(REMOVE_DUPLICATES RequiredHeaders)

  if(GeneratedHeaders)
    list(REMOVE_DUPLICATES GeneratedHeaders)
  endif()

  # Here we now have:
  #  RequiredHeaders: flat list of all of the headers from the library we are currently wrapping and
  #                   all of the libraries that it depends on

  # Export the required headers variable up to the next level so that further SWIG targets can look it up
  #set(exportname "${NAME}RequiredHeaders")

  # Oh, and also export it to this level, for peers, like the Utilities breakouts and the Model breakouts
  set(${exportname} "${RequiredHeaders}")
  set(${exportname} "${RequiredHeaders}" PARENT_SCOPE)

  if(NOT TARGET ${PARENT_TARGET}_GeneratedHeaders)
    if ("${NAME}" STREQUAL "OpenStudioUtilitiesCore")
      # Workaround appending GenerateIddFactoryRun to GeneratedHeaders, so we ensure that the custom command below actually is called AFTER
      # GenerateIddFactoryRun has been called
      list(APPEND GeneratedHeaders "GenerateIddFactoryRun")
    endif()

    # Add a command to generate the generated headers discovered at this point.
    add_custom_command(
      OUTPUT "${PROJECT_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
      COMMAND ${CMAKE_COMMAND} -E touch "${PROJECT_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
      DEPENDS ${GeneratedHeaders}
    )

    # And a target that calls the above command
    add_custom_target(${PARENT_TARGET}_GeneratedHeaders
      SOURCES "${PROJECT_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
    )

    # Now we say that our PARENT_TARGET depends on this new GeneratedHeaders
    # target. This is where the magic happens. By making both the parent
    # and this *_swig.cxx files below rely on this new target we force all
    # of the generated files to be generated before either the
    # PARENT_TARGET is built or the cxx files are generated. This solves the problems with
    # parallel builds trying to generate the same file multiple times while still
    # allowing files to compile in parallel
    add_dependencies(${PARENT_TARGET} ${PARENT_TARGET}_GeneratedHeaders)
  endif()

  ##
  ## Finish requirements gathering
  ##

  if(WIN32)
    set(SWIG_DEFINES "-D_WINDOWS")
    set(SWIG_COMMON "-Fmicrosoft")
  endif()

  # Ruby bindings

  # check if this is the OpenStudioUtilities project
  string(REGEX MATCH "OpenStudioUtilities" IS_UTILTIES "${NAME}")

  set(swig_target "ruby_${NAME}")

  # wrapper file output
  set(SWIG_WRAPPER "ruby_${NAME}_wrap.cxx")
  set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")
  # ruby dlls should be all lowercase
  string(TOLOWER "${NAME}" LOWER_NAME)

  # utilities goes into OpenStudio:: directly, everything else is nested
  if(IS_UTILTIES)
    set(MODULE "OpenStudio")
  else()
    set(MODULE "OpenStudio::${SIMPLENAME}")
  endif()

  if(DEFINED OpenStudioCore_SWIG_INCLUDE_DIR)
    set(extra_includes "-I${OpenStudioCore_SWIG_INCLUDE_DIR}")
  endif()

  if(DEFINED OpenStudioCore_DIR)
    set(extra_includes2 "-I${OpenStudioCore_DIR}/src")
  endif()

  set(this_depends ${ParentSWIGWrappers})
  list(APPEND this_depends ${PARENT_TARGET}_GeneratedHeaders)
  list(APPEND this_depends ${RequiredHeaders})
  list(REMOVE_DUPLICATES this_depends)
  set(${NAME}_SWIG_Depends "${this_depends}")
  set(${NAME}_SWIG_Depends "${this_depends}" PARENT_SCOPE)

  #message(STATUS "${${NAME}_SWIG_Depends}")

  #set(RUBY_AUTODOC "")
  #if(BUILD_DOCUMENTATION)
  #  set(RUBY_AUTODOC -features autodoc=1)
  #endif()

  add_custom_command(
    OUTPUT "${SWIG_WRAPPER}"
    COMMAND ${CMAKE_COMMAND} -E env SWIG_LIB="${SWIG_LIB}"
            "${SWIG_EXECUTABLE}"
            "-ruby" "-c++" "-fvirtual" "-I${PROJECT_SOURCE_DIR}/src" "-I${PROJECT_BINARY_DIR}/src" "${extra_includes}" "${extra_includes2}" ${RUBY_AUTODOC}
            -module "${MODULE}" -initname "${LOWER_NAME}"
            "-I${PROJECT_SOURCE_DIR}/ruby"
            -o "${SWIG_WRAPPER_FULL_PATH}"
            "${SWIG_DEFINES}" ${SWIG_COMMON} "${KEY_I_FILE}"
    DEPENDS ${this_depends}
  )

  if(MAXIMIZE_CPU_USAGE)
    add_custom_target(${swig_target}_swig
      SOURCES "${SWIG_WRAPPER}"
    )
    add_dependencies(${PARENT_TARGET} ${swig_target}_swig)
  endif()

  include_directories(${PROJECT_SOURCE_DIR})

  add_library(
    ${swig_target} OBJECT
    ${SWIG_WRAPPER}
  )


  # run rdoc
  if(BUILD_DOCUMENTATION)
    add_custom_target(${swig_target}_rdoc
      ${CMAKE_COMMAND} -E chdir "${PROJECT_BINARY_DIR}/ruby/${CMAKE_CFG_INTDIR}" "${CONAN_BIN_DIRS_OPENSTUDIO_RUBY}/ruby" "${PROJECT_SOURCE_DIR}/../developer/ruby/SwigWrapToRDoc.rb" "${PROJECT_BINARY_DIR}/" "${SWIG_WRAPPER_FULL_PATH}" "${NAME}"
      DEPENDS ${SWIG_WRAPPER}
    )

    # Add this documentation target to the list of all targets
    list(APPEND ALL_RDOC_TARGETS ${swig_target}_rdoc)
    set(ALL_RDOC_TARGETS "${ALL_RDOC_TARGETS}" PARENT_SCOPE)

  endif()

  #set_target_properties(${swig_target} PROPERTIES PREFIX "")
  #set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${LOWER_NAME}")
  #if(APPLE)
  #  set_target_properties(${swig_target} PROPERTIES SUFFIX ".bundle" )
  #  #set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
  #  #set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined suppress -flat_namespace")
  #endif()


  if(MSVC)
    #set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-DRUBY_EXTCONF_H=<osruby_config.h> -DRUBY_EMBEDDED /bigobj /wd4996") ## /wd4996 suppresses deprecated warning
    set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996 /wd5033 /wd4244") ## /wd4996 suppresses deprecated warning, /wd5033 supresses 'register' is no longer a supported storage class, /wd4244 supresses conversion from 'type1' to 'type2' possible loss of data
  elseif(UNIX)
    # If 'AppleClang' or 'Clang'
    if("${CMAKE_CXX_COMPILER_ID}" MATCHES "^(Apple)?Clang$")
      # Prevent excessive warnings from generated swig files, suppress deprecated declarations
      # Suppress 'register' storage class specified warnings (coming from Ruby)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-dynamic-class-memaccess -Wno-deprecated-declarations -Wno-sign-compare -Wno-register")
    else()
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-sign-compare -Wno-register -Wno-conversion-null")
    endif()
  endif()

  #if(CMAKE_COMPILER_IS_GNUCXX)
  #  if(GCC_VERSION VERSION_GREATER 4.6 OR GCC_VERSION VERSION_EQUAL 4.6)
  #    set_source_files_properties(${SWIG_WRAPPER} PROPERTIES COMPILE_FLAGS "-Wno-uninitialized -Wno-unused-but-set-variable")
  #  else()
  #    set_source_files_properties(${SWIG_WRAPPER} PROPERTIES COMPILE_FLAGS "-Wno-uninitialized")
  #  endif()
  #endif()

  set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ruby/")
  #if(RUBY_VERSION_MAJOR EQUAL "2" AND MSVC)
  #  # Ruby 2 requires modules to have a .so extension, even on windows
  #  set_target_properties(${swig_target} PROPERTIES SUFFIX ".so")
  #endif()
  set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/ruby/")
  set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ruby/")
  target_link_libraries(${swig_target} ${${PARENT_TARGET}_depends})
  target_include_directories(${swig_target} PRIVATE ${RUBY_INCLUDE_DIRS})
  add_dependencies(${swig_target} ${PARENT_TARGET})

  # QT-Separation-Move
  target_include_directories(${swig_target} PUBLIC ${QT_INCLUDES})
  target_compile_definitions(${swig_target} PUBLIC ${QT_DEFS})

  ####Remove binding install related stuff. At least for now. Might need some of this to support sketchup
  ####if(APPLE)
  ####  set(_NAME "${LOWER_NAME}.bundle")
  ####  # the following script will change the bindings to prefer the version of libruby included with SketchUp to the system library, preventing loading two different copies of libruby
  ####  add_custom_command(TARGET ${swig_target} POST_BUILD COMMAND ${RUBY_EXECUTABLE} "${PROJECT_SOURCE_DIR}/SketchUpInstallName.rb" "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ruby/${_NAME}")
  ####elseif(RUBY_VERSION_MAJOR EQUAL "2" AND MSVC)
  ####  set(_NAME "${LOWER_NAME}.so")
  ####else()
  ####  set(_NAME "${LOWER_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  ####endif()

  ####if(WIN32 OR APPLE)
  ####  install(TARGETS ${swig_target} DESTINATION Ruby/openstudio/)


  ####  install(CODE "
  ####    #message(\"INSTALLING SWIG_TARGET: ${swig_target}  with NAME = ${_NAME}\")
  ####    include(GetPrerequisites)
  ####    get_prerequisites(\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/${_NAME} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")
  ####    #message(\"PREREQUISITES = \${PREREQUISITES}\")


  ####    if(WIN32)
  ####      list(REVERSE PREREQUISITES)
  ####    endif()

  ####    foreach(PREREQ IN LISTS PREREQUISITES)
  ####
  ####      if(APPLE AND PREREQ MATCHES \".*libruby.*\")
  ####        # skip updating references to libruby, we do not install this with the bindings
  ####      else()
  ####        gp_resolve_item(\"\" \${PREREQ} \"\" \"${Prereq_Dirs}\" resolved_item_var)
  ####        execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\")
  ####
  ####        get_filename_component(PREREQNAME \${resolved_item_var} NAME)
  ####
  ####        if(APPLE)
  ####          execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/${_NAME}\")
  ####          foreach(PR IN LISTS PREREQUISITES)
  ####            gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
  ####            get_filename_component( PRNAME \${PRPATH} NAME)
  ####            execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\${PREREQNAME}\")
  ####          endforeach()
  ####        else()
  ####          if(EXISTS \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\")
  ####            file(READ \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" TEXT)
  ####          else()
  ####            set(TEXT \"\")
  ####          endif()
  ####          string(REGEX MATCH \${PREREQNAME} MATCHVAR \"\${TEXT}\")
  ####          if(NOT (\"\${MATCHVAR}\" STREQUAL \"\${PREREQNAME}\"))
  ####            file(APPEND \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" \"DL::dlopen \\\"\\\#{File.dirname(__FILE__)}/\${PREREQNAME}\\\"\n\")
  ####          endif()
  ####      endif()
  ####      endif()

  ####    endforeach()
  ####  ")
  ####else()
  ####  install(TARGETS ${swig_target} DESTINATION "${RUBY_MODULE_ARCH_DIR}")
  ####endif()
  ####if(UNIX)
  ####  # do not write file on unix, existence of file is checked before it is loaded
  ####  #install(CODE "
  ####  #  file(WRITE \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" \"# Nothing to see here\")
  ####  #")
  ####endif()

  execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\")

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_TARGETS "${swig_target}")
  set(ALL_RUBY_BINDING_TARGETS "${ALL_RUBY_BINDING_TARGETS}" PARENT_SCOPE)

  # Doesn't look like this is used
  # add this target to a "global" variable so ruby tests can require these
  #list(APPEND ALL_RDOCIFY_FILES "${SWIG_WRAPPER}")
  #set(ALL_RDOCIFY_FILES "${ALL_RDOCIFY_FILES}" PARENT_SCOPE)

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_WRAPPERS "${SWIG_WRAPPER}")
  set(ALL_RUBY_BINDING_WRAPPERS "${ALL_RUBY_BINDING_WRAPPERS}" PARENT_SCOPE)

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_WRAPPERS_FULL_PATH "${SWIG_WRAPPER_FULL_PATH}")
  set(ALL_RUBY_BINDING_WRAPPERS_FULL_PATH "${ALL_RUBY_BINDING_WRAPPERS_FULL_PATH}" PARENT_SCOPE)

  # Python bindings
  if(BUILD_PYTHON_BINDINGS)
    set(swig_target "python_${NAME}")

    # utilities goes into OpenStudio. directly, everything else is nested
    # DLM: SWIG generates a file ${MODULE}.py for each module, however we have several libraries in the same module
    # so these clobber each other.  Making these unique, e.g. MODULE = TOLOWER "${NAME}", generates unique .py wrappers
    # but the module names are unknown and the bindings fail to load.  I think we need to write our own custom OpenStudio.py
    # wrapper that imports all of the libraries/python wrappers into the appropriate modules.
    # http://docs.python.org/2/tutorial/modules.html
    # http://docs.python.org/2/library/imp.html

    set(MODULE ${LOWER_NAME})

    set(SWIG_WRAPPER "python_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(PYTHON_GENERATED_SRC_DIR "${PROJECT_BINARY_DIR}/python_wrapper/generated_sources/")
    file(MAKE_DIRECTORY ${PYTHON_GENERATED_SRC_DIR})

    set(PYTHON_GENERATED_SRC "${PYTHON_GENERATED_SRC_DIR}/${LOWER_NAME}.py")

    set(PYTHON_AUTODOC "")
    if(BUILD_DOCUMENTATION)
      set(PYTHON_AUTODOC -features autodoc=1)
    endif()


    # Add the -py3 flag if the version used is Python 3
    set(SWIG_PYTHON_3_FLAGS "")
    if (Python_VERSION_MAJOR)
      if (Python_VERSION_MAJOR EQUAL 3)
        set(SWIG_PYTHON_3_FLAGS "-py3;-relativeimport")
        message(STATUS "${MODULE} - Building SWIG Bindings for Python 3")
      else()
        message(STATUS "${MODULE} - Building SWIG Bindings for Python 2")
      endif()
    else()
      # Python2 has been EOL since January 1, 2020
      set(SWIG_PYTHON_3_FLAGS "-py3;-relativeimport")
      message(STATUS "${MODULE} - Couldnt determine version of Python - Building SWIG Bindings for Python 3")
    endif()

    add_custom_command(
      OUTPUT "${SWIG_WRAPPER_FULL_PATH}" "${PYTHON_GENERATED_SRC}"
      COMMAND ${CMAKE_COMMAND} -E env SWIG_LIB="${SWIG_LIB}"
              "${SWIG_EXECUTABLE}"
              "-python" ${SWIG_PYTHON_3_FLAGS} "-c++" ${PYTHON_AUTODOC}
              -outdir ${PYTHON_GENERATED_SRC_DIR} "-I${PROJECT_SOURCE_DIR}/src" "-I${PROJECT_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}
    )


    set_source_files_properties(${SWIG_WRAPPER_FULL_PATH} PROPERTIES GENERATED TRUE)
    set_source_files_properties(${PYTHON_GENERATED_SRC} PROPERTIES GENERATED TRUE)

    #add_custom_target(${SWIG_TARGET}
    #  DEPENDS ${SWIG_WRAPPER_FULL_PATH}
    #)

    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME _${LOWER_NAME})
    set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/python/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/python/")
    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996 /wd4005") ## /wd4996 suppresses deprecated warning, /wd4005 suppresses macro redefinition warning
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".pyd")
    elseif(UNIX)
      # TODO: Probably something to be done here...

      # set_target_properties(${swig_target}
      #   PROPERTIES
      #   BUILD_RPATH $<TARGET_FILE_DIR:openstudiolib>
      #   INSTALL_RPATH ${CMAKE_INSTALL_LIBDIR}
      # )
      # set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-Wl,-rpath,./")
      if(APPLE AND NOT CMAKE_COMPILER_IS_GNUCXX)
        set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-dynamic-class-memaccess -Wno-deprecated-declarations -Wno-sign-compare")
      else()
        set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-sign-compare")
      endif()
    endif()

    file(MAKE_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/openstudio/")
    set(COPY_PYTHON_GENERATED_SRC "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/${LOWER_NAME}.py")
    set(MODIFIED_PYTHON_GENERATED_SRC "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/openstudio/${LOWER_NAME}.py")
    add_custom_command(TARGET ${swig_target}
      POST_BUILD
      # OUTPUT "${MODIFIED_PYTHON_GENERATED_SRC}"
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${PYTHON_GENERATED_SRC}" "${COPY_PYTHON_GENERATED_SRC}"
      COMMAND "${CMAKE_COMMAND}" -P "${PROJECT_SOURCE_DIR}/python/FixPythonImports.cmake" "${PYTHON_GENERATED_SRC}" "${MODIFIED_PYTHON_GENERATED_SRC}"
      DEPENDS "${PYTHON_GENERATED_SRC}"
    )
    set_source_files_properties(${MODIFIED_PYTHON_GENERATED_SRC} PROPERTIES GENERATED TRUE)

    # TODO: for local testing, PYTHON_GENERATED_SRC should go into Products/python next to the .so files
    install(FILES "${MODIFIED_PYTHON_GENERATED_SRC}" DESTINATION Python COMPONENT "Python")
    install(TARGETS ${swig_target} DESTINATION Python COMPONENT "Python")


    # TODO: really unusre where former PYTHON_Libraries was doing and I really doubt linking to the python libs is something we want... We're not
    # trying to make a CLI here
    target_link_libraries(${swig_target} ${${PARENT_TARGET}_depends}) # ${Python_LIBRARIES})
    add_dependencies(${swig_target} ${PARENT_TARGET})

    # add this target to a "global" variable so python tests can require these
    list(APPEND ALL_PYTHON_BINDING_TARGETS "${swig_target}")
    set(ALL_PYTHON_BINDING_TARGETS "${ALL_PYTHON_BINDING_TARGETS}" PARENT_SCOPE)

    list(APPEND ALL_PYTHON_BINDING_DEPENDS "${${PARENT_TARGET}_depends}")
    set(ALL_PYTHON_BINDING_DEPENDS "${ALL_PYTHON_BINDING_DEPENDS}" PARENT_SCOPE)

    list(APPEND ALL_PYTHON_BINDING_WRAPPERS "${SWIG_WRAPPER}")
    set(ALL_PYTHON_BINDING_WRAPPERS "${ALL_PYTHON_BINDING_WRAPPERS}" PARENT_SCOPE)

    list(APPEND ALL_PYTHON_BINDING_WRAPPERS_FULL_PATH "${SWIG_WRAPPER_FULL_PATH}")
    set(ALL_PYTHON_BINDING_WRAPPERS_FULL_PATH "${ALL_PYTHON_BINDING_WRAPPERS_FULL_PATH}" PARENT_SCOPE)

  endif()

  # csharp
  if(BUILD_CSHARP_BINDINGS)
    set(swig_target "csharp_${NAME}")

    # keep the following lists aligned with translator_wrappers in \openstudiocore\csharp\CMakeLists.txt
    set( translator_names
      OpenStudioAirflow
      OpenStudioEnergyPlus
      OpenStudioGBXML
      OpenStudioISOModel
      OpenStudioRadiance
      OpenStudioSDD
    )

    set( model_names
      OpenStudioMeasure
      OpenStudioModel
      OpenStudioModelAirflow
      OpenStudioModelAvailabilityManager
      OpenStudioModelCore
      OpenStudioModelGenerators
      OpenStudioModelGeometry
      OpenStudioModelHVAC
      OpenStudioModelPlantEquipmentOperationScheme
      OpenStudioModelRefrigeration
      OpenStudioModelResources
      OpenStudioModelSetpointManager
      OpenStudioModelSimulation
      OpenStudioModelStraightComponent
      OpenStudioModelZoneHVAC
      OpenStudioOSVersion
      OpenStudioModelEditor
    )

    if(IS_UTILTIES)
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    else()
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    endif()

    set(SWIG_WRAPPER "csharp_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")
    set(SWIG_TARGET "generate_csharp_${NAME}_wrap")

    list(FIND translator_names ${NAME} name_found)
    if( name_found GREATER -1 )
      if(MSVC)
        set(CSHARP_OUTPUT_NAME "openstudio_translators_csharp.dll")
      else()
        set(CSHARP_OUTPUT_NAME "libopenstudio_translators_csharp.so")
      endif()
    else()
      list(FIND model_names ${NAME} name_found)
      if( name_found GREATER -1 )
        if(MSVC)
          set(CSHARP_OUTPUT_NAME "openstudio_model_csharp.dll")
        else()
          set(CSHARP_OUTPUT_NAME "libopenstudio_model_csharp.so")
        endif()
      else()
        if(MSVC)
          set(CSHARP_OUTPUT_NAME "openstudio_csharp.dll")
        else()
          set(CSHARP_OUTPUT_NAME "libopenstudio_csharp.so")
        endif()
      endif()
    endif()

    set(CSHARP_GENERATED_SRC_DIR "${PROJECT_BINARY_DIR}/csharp_wrapper/generated_sources/${NAME}")
    file(MAKE_DIRECTORY ${CSHARP_GENERATED_SRC_DIR})

    set(CSHARP_AUTODOC "")
    if(BUILD_DOCUMENTATION)
      set(CSHARP_AUTODOC -features autodoc=1)
    endif()

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER_FULL_PATH}
      COMMAND "${CMAKE_COMMAND}" -E remove_directory "${CSHARP_GENERATED_SRC_DIR}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${CSHARP_GENERATED_SRC_DIR}"
      COMMAND ${CMAKE_COMMAND} -E env SWIG_LIB="${SWIG_LIB}"
              "${SWIG_EXECUTABLE}"
              "-csharp" "-c++" -namespace ${NAMESPACE} ${CSHARP_AUTODOC}
              -outdir "${CSHARP_GENERATED_SRC_DIR}"  "-I${PROJECT_SOURCE_DIR}/src" "-I${PROJECT_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              -dllimport "${CSHARP_OUTPUT_NAME}"
              "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}

      )

      add_custom_target(${SWIG_TARGET}
        DEPENDS ${SWIG_WRAPPER_FULL_PATH}
      )


    #add_library(
    #  ${swig_target}
    #  STATIC
    #  ${SWIG_WRAPPER}
    #)

    #set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${CSHARP_OUTPUT_NAME}")
    #set_target_properties(${swig_target} PROPERTIES PREFIX "")
    #set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/csharp/")
    #set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/csharp/")
    #set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/csharp/")
    #if(MSVC)
    #  set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996")  ## /wd4996 suppresses deprecated warnings
    #endif()
    #target_link_libraries(${swig_target} ${PARENT_TARGET})

    #ADD_DEPENDENCIES("${swig_target}" "${PARENT_TARGET}_resources")
    #    add_dependencies(${SWIG_TARGET} ${PARENT_TARGET})

    # add this target to a "global" variable so csharp tests can require these
    list(APPEND ALL_CSHARP_BINDING_DEPENDS "${${PARENT_TARGET}_depends}")
    set(ALL_CSHARP_BINDING_DEPENDS "${ALL_CSHARP_BINDING_DEPENDS}" PARENT_SCOPE)

    list(APPEND ALL_CSHARP_WRAPPER_FILES "${SWIG_WRAPPER_FULL_PATH}")
    set(ALL_CSHARP_WRAPPER_FILES "${ALL_CSHARP_WRAPPER_FILES}" PARENT_SCOPE)

    list(APPEND ALL_CSHARP_WRAPPER_TARGETS "${SWIG_TARGET}")
    set(ALL_CSHARP_WRAPPER_TARGETS "${ALL_CSHARP_WRAPPER_TARGETS}" PARENT_SCOPE)

    #if(WIN32)
    #  install(TARGETS ${swig_target} DESTINATION CSharp/openstudio/)
    #
    #  install(CODE "
    #    include(GetPrerequisites)
    #    get_prerequisites(\${CMAKE_INSTALL_PREFIX}/CSharp/openstudio/openstudio_${NAME}_csharp.dll PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")
    #
    #    if(WIN32)
    #      list(REVERSE PREREQUISITES)
    #    endif()
    #
    #    foreach(PREREQ IN LISTS PREREQUISITES)
    #      gp_resolve_item(\"\" \${PREREQ} \"\" \"${Prereq_Dirs}\" resolved_item_var)
    #      execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/CSharp/openstudio/\")
    #
    #      get_filename_component(PREREQNAME \${resolved_item_var} NAME)
    #    endforeach()
    #  ")
    #endif()
  endif()

  # java
  if(BUILD_JAVA_BINDINGS)
    set(swig_target "java_${NAME}")

    string(SUBSTRING ${NAME} 10 -1 SIMPLIFIED_NAME)
    string(TOLOWER ${SIMPLIFIED_NAME} SIMPLIFIED_NAME)

    if(IS_UTILTIES)
      set(NAMESPACE "gov.nrel.openstudio")
      set(MODULE "${SIMPLIFIED_NAME}_global")
    else()
      #set( NAMESPACE "OpenStudio.${NAME}")
      set( NAMESPACE "gov.nrel.openstudio")
      set( MODULE "${SIMPLIFIED_NAME}_global")
    endif()

    set(SWIG_WRAPPER "java_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(JAVA_OUTPUT_NAME "${NAME}_java")
    set(JAVA_GENERATED_SRC_DIR "${PROJECT_BINARY_DIR}/java_wrapper/generated_sources/${NAME}")
    file(MAKE_DIRECTORY ${JAVA_GENERATED_SRC_DIR})

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER}
      COMMAND "${CMAKE_COMMAND}" -E remove_directory "${JAVA_GENERATED_SRC_DIR}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${JAVA_GENERATED_SRC_DIR}"
      COMMAND ${CMAKE_COMMAND} -E env SWIG_LIB="${SWIG_LIB}"
              "${SWIG_EXECUTABLE}"
              "-java" "-c++"
              -package ${NAMESPACE}
              #-features autodoc=1
              -outdir "${JAVA_GENERATED_SRC_DIR}"  "-I${PROJECT_SOURCE_DIR}/src" "-I${PROJECT_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              #-dllimport "${JAVA_OUTPUT_NAME}"
              "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}

    )

    if(MAXIMIZE_CPU_USAGE)
      add_custom_target(${swig_target}_swig
        SOURCES "${SWIG_WRAPPER}"
        )
      add_dependencies(${PARENT_TARGET} ${swig_target}_swig)
    endif()


    include_directories("${JAVA_INCLUDE_PATH}" "${JAVA_INCLUDE_PATH2}")

    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${JAVA_OUTPUT_NAME}")
    #set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/java/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/java/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/java/")
    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996") ## /wd4996 suppresses deprecated warnings
      set(final_name "${JAVA_OUTPUT_NAME}.dll")
    elseif(UNIX)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-sign-compare")
    endif()

    target_link_libraries(${swig_target} ${PARENT_TARGET} ${JAVA_JVM_LIBRARY})
    if(APPLE)
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".dylib")
      set(final_name "lib${JAVA_OUTPUT_NAME}.dylib")
    endif()

    #add_dependencies("${swig_target}" "${PARENT_TARGET}_resources")

    # add this target to a "global" variable so java tests can require these
    list(APPEND ALL_JAVA_BINDING_TARGETS "${swig_target}")
    set(ALL_JAVA_BINDING_TARGETS "${ALL_JAVA_BINDING_TARGETS}" PARENT_SCOPE)

    list(APPEND ALL_JAVA_SRC_DIRECTORIES "${JAVA_GENERATED_SRC_DIR}")
    set(ALL_JAVA_SRC_DIRECTORIES "${ALL_JAVA_SRC_DIRECTORIES}" PARENT_SCOPE)


    if(WIN32 OR APPLE)
      install(TARGETS ${swig_target} DESTINATION Java/openstudio/)

      install(CODE "
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/Java/openstudio/${final_name} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")

        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item(\"\" \${PREREQ} \"\" \"${Prereq_Dirs}\" resolved_item_var)
          execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/\")

          get_filename_component(PREREQNAME \${resolved_item_var} NAME)

          if(APPLE)
            execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/${final_name}\")
            foreach(PR IN LISTS PREREQUISITES)
              gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
              get_filename_component(PRNAME \${PRPATH} NAME)
              execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/\${PREREQNAME}\")
            endforeach()
          endif()
        endforeach()
      ")
    else()
      install(TARGETS ${swig_target} DESTINATION "lib/openstudio-${OpenStudio_VERSION}/java")
    endif()
  endif()


  # v8
  if(BUILD_V8_BINDINGS)
    set(swig_target "v8_${NAME}")

    if(IS_UTILTIES)
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    else()
      #set(NAMESPACE "OpenStudio.${NAME}")
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    endif()

    set(SWIG_WRAPPER "v8_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(v8_OUTPUT_NAME "${NAME}")
    #set(CSHARP_GENERATED_SRC_DIR "${PROJECT_BINARY_DIR}/csharp_wrapper/generated_sources/${NAME}")
    #file(MAKE_DIRECTORY ${CSHARP_GENERATED_SRC_DIR})

    if(BUILD_NODE_MODULES)
      set(V8_DEFINES "-DBUILD_NODE_MODULE")
      set(SWIG_ENGINE "-node")
    else()
      set(V8_DEFINES "")
      set(SWIG_ENGINE "-v8")
    endif()

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER}
      COMMAND ${CMAKE_COMMAND} -E env SWIG_LIB="${SWIG_LIB}"
              "${SWIG_EXECUTABLE}"
              "-javascript" ${SWIG_ENGINE} "-c++"
              #-namespace ${NAMESPACE}
              #-features autodoc=1
              #-outdir "${CSHARP_GENERATED_SRC_DIR}"
              "-I${PROJECT_SOURCE_DIR}/src" "-I${PROJECT_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              "${SWIG_DEFINES}" ${V8_DEFINES} ${SWIG_COMMON} ${KEY_I_FILE}
              DEPENDS ${this_depends}

    )

    if(BUILD_NODE_MODULES)
      include_directories("${NODE_INCLUDE_DIR}" "${NODE_INCLUDE_DIR}/deps/v8/include" "${NODE_INCLUDE_DIR}/deps/uv/include" "${NODE_INCLUDE_DIR}/src")
    else()
      include_directories(${V8_INCLUDE_DIR})
    endif()

    if(MAXIMIZE_CPU_USAGE)
      add_custom_target(${swig_target}_swig
        SOURCES "${SWIG_WRAPPER}"
        )
      add_dependencies(${PARENT_TARGET} ${swig_target}_swig)
    endif()


    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME ${v8_OUTPUT_NAME})
    set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set(_NAME "${v8_OUTPUT_NAME}.node")
    if(BUILD_NODE_MODULES)
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".node")
    endif()
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/v8/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/v8/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/v8/")

    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /DBUILDING_NODE_EXTENSION /wd4996")  ## /wd4996 suppresses deprecated warnings
    elseif(UNIX)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-DBUILDING_NODE_EXTENSION -Wno-deprecated-declarations -Wno-sign-compare")
    endif()

    if(APPLE)
      set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined suppress -flat_namespace")
    endif()
    target_link_libraries(${swig_target} ${PARENT_TARGET})

    #add_dependencies("${swig_target}" "${PARENT_TARGET}_resources")

    # add this target to a "global" variable so v8 tests can require these
    list(APPEND ALL_V8_BINDING_TARGETS "${swig_target}")
    set(ALL_V8_BINDING_TARGETS "${ALL_V8_BINDING_TARGETS}" PARENT_SCOPE)

    if(BUILD_NODE_MODULES)
      set(V8_TYPE "node")
    else()
      set(V8_TYPE "v8")
    endif()

    if(WIN32 OR APPLE)
      install(TARGETS ${swig_target} DESTINATION "${V8_TYPE}/openstudio/")

      install(CODE "
        #message(\"INSTALLING SWIG_TARGET: ${swig_target}  with NAME = ${_NAME}\")
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/${_NAME} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")
        #message(\"PREREQUISITES = \${PREREQUISITES}\")


        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item(\"\" \${PREREQ} \"\" \"${Prereq_Dirs}\" resolved_item_var)
          #message(\"prereq = ${PREREQ}  resolved = ${resolved_item_var} \")
          execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/\")

          get_filename_component(PREREQNAME \${resolved_item_var} NAME)

          if(APPLE)
            execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/${_NAME}\")
            foreach(PR IN LISTS PREREQUISITES)
              gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
              get_filename_component(PRNAME \${PRPATH} NAME)
              execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/\${PREREQNAME}\")
            endforeach()
          endif()
        endforeach()
        if(APPLE)
          # QT-Separation-Move
          file(COPY \"${QT_LIBRARY_DIR}/QtGui.framework/Resources/qt_menu.nib\"
            DESTINATION \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/Resources/\"
          )
        endif()
      ")
    else()
      install(TARGETS ${swig_target} DESTINATION "lib/openstudio-${OpenStudio_VERSION}/${V8_TYPE}")
    endif()
  endif()


endmacro() # End of MAKE_SWIG_TARGET

# add target dependencies
# this will add targets to a "global" variable marking
# them to have their dependencies installed later.
macro(ADD_DEPENDENCIES_FOR_TARGET target)
  get_target_property(target_path ${target} LOCATION_DEBUG)
  list(APPEND DEPENDENCY_TARGETS ${target_path})
  set(DEPENDENCY_TARGETS "${DEPENDENCY_TARGETS}" PARENT_SCOPE)
endmacro()


# run energyplus
# appends output (eplusout.err) to list ENERGYPLUS_OUTPUTS
macro(RUN_ENERGYPLUS FILENAME DIRECTORY WEATHERFILE)
  list(APPEND ENERGYPLUS_OUTPUTS "${DIRECTORY}/eplusout.err")
  add_custom_command(
    OUTPUT "${DIRECTORY}/eplusout.err"
    COMMAND ${CMAKE_COMMAND} -E copy "${DIRECTORY}/${FILENAME}" "${DIRECTORY}/in.idf"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_IDD}" "${DIRECTORY}/Energy+.idd"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_WEATHER_DIR}/${WEATHERFILE}" "${DIRECTORY}/in.epw"
    COMMAND ${CMAKE_COMMAND} -E chdir "${DIRECTORY}" "${ENERGYPLUS_EXE}" ">" "${DIRECTORY}/screen.out"
    DEPENDS "${ENERGYPLUS_IDD}" "${ENERGYPLUS_WEATHER_DIR}/${WEATHERFILE}" "${ENERGYPLUS_EXE}" "${CMAKE_CURRENT_BINARY_DIR}/${DIRECTORY}/${FILENAME}"
    COMMENT "Updating EnergyPlus simulation in ${CMAKE_CURRENT_BINARY_DIR}/${DIRECTORY}/, this may take a while"
  )
endmacro()

# run energyplus
# appends output (eplusout.err) to list ENERGYPLUS_OUTPUTS
macro(RUN_ENERGYPLUS_CUSTOMEPW FILENAMEANDPATH WEATHERFILENAMEANDPATH RUN_DIRECTORY)
  list(APPEND ENERGYPLUS_OUTPUTS "${RUN_DIRECTORY}/eplusout.err")
  add_custom_command(
    OUTPUT "${RUN_DIRECTORY}/eplusout.err"
    COMMAND ${CMAKE_COMMAND} -E copy "${FILENAMEANDPATH}" "${RUN_DIRECTORY}/in.idf"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_IDD}" "${RUN_DIRECTORY}/Energy+.idd"
    COMMAND ${CMAKE_COMMAND} -E copy "${WEATHERFILENAMEANDPATH}" "${RUN_DIRECTORY}/in.epw"
    COMMAND ${CMAKE_COMMAND} -E chdir "${RUN_DIRECTORY}" "${ENERGYPLUS_EXE}" ">" "${RUN_DIRECTORY}/screen.out"
    DEPENDS "${ENERGYPLUS_IDD}" "${CMAKE_CURRENT_BINARY_DIR}/${WEATHERFILENAMEANDPATH}" "${ENERGYPLUS_EXE}" "${CMAKE_CURRENT_BINARY_DIR}/${FILENAMEANDPATH}"
    COMMENT "Updating EnergyPlus simulation in ${CMAKE_CURRENT_BINARY_DIR}/${RUN_DIRECTORY}/, this may take a while"
  )
endmacro()

# adds custom command to update a resource
macro(UPDATE_RESOURCES SRCS)
  foreach(SRC ${SRCS})
    add_custom_command(
      OUTPUT "${SRC}"
      COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}" "${SRC}"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}"
    )
  endforeach()
endmacro()

# adds custom command to update a resource via configure
macro(CONFIGURE_RESOURCES SRCS)
  foreach(SRC ${SRCS})
    # Would like to wrap this up in a custom command, but no luck thus far.
    # ADD_CUSTOM_COMMAND(
    #  OUTPUT "${SRC}"
    #  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}"
    #  COMMAND ${CMAKE_COMMAND}
    #  ARGS -Dfile_name=${SRC} -Dinclude_name=${include_name} -E

      configure_file( "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}" "${SRC}" )

    #)
  endforeach()
endmacro()

# link target with debug and release libs
function(LINK_DEBUG_AND_RELEASE this_target debug_libs release_libs)
  list(LENGTH debug_libs len1)
  list(LENGTH release_libs len2)

  if (NOT len1 EQUAL len2)
    message(SEND_ERROR "Unequal lists passed to LINK_DEBUG_AND_RELEASE")
  endif()

  math(EXPR len "${len1} - 1")

  foreach(i RANGE ${len})
    list(GET debug_libs ${i} debug_lib)
    list(GET release_libs ${i} release_lib)
    target_link_libraries(${this_target} debug ${debug_lib} optimized ${release_lib})
  endforeach()

endfunction()

# adds custom command to update a resource via configure
macro(CONFIGURE_FILE_WITH_CHECKSUM INPUT_FILE OUTPUT_FILE)
  SET(TMP_OUTPUT_FILE "${OUTPUT_FILE}.tmp")

  if(NOT EXISTS "${OUTPUT_FILE}")
    configure_file( "${INPUT_FILE}" "${OUTPUT_FILE}" )
  else()
    configure_file( "${INPUT_FILE}" "${TMP_OUTPUT_FILE}" )
    file(MD5 "${OUTPUT_FILE}" EXISTING_HASH)
    file(MD5 "${TMP_OUTPUT_FILE}" NEW_HASH)
    if (NOT "${EXISTING_HASH}" MATCHES "${NEW_HASH}")
      configure_file( "${INPUT_FILE}" "${OUTPUT_FILE}" )
    endif()
  endif()
endmacro()

