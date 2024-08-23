#!/usr/bin/env bash

remove_expectWarning() {
    # Fix "Call to undefined method CurlTest\CurlTest::expectWarning()".
    if sed v < /dev/null 2> /dev/null; then
        sed -i"" -e "/->expectWarning(/d" "./PHPCurlClass/PHP"*
    else
        sed -i "" -e "/->expectWarning(/d" "./PHPCurlClass/PHP"*
    fi
}

replace_assertStringContainsString() {
    # -->assertStringContainsString(
    # +->assertContains(
    find='->assertStringContainsString('
    replace='->assertContains('
    if sed v < /dev/null 2> /dev/null; then
        sed -i"" -e "s/${find}/${replace}/" "./PHPCurlClass/PHP"*
    else
        sed -i "" -e "s/${find}/${replace}/" "./PHPCurlClass/PHP"*
    fi
}

replace_assertMatchesRegularExpression() {
    # -->assertMatchesRegularExpression(
    # +->assertRegExp(
    find='->assertMatchesRegularExpression('
    replace='->assertRegExp('
    if sed v < /dev/null 2> /dev/null; then
        sed -i"" -e"s/${find}/${replace}/" "./PHPCurlClass/PHP"*
    else
        sed -i "" -e"s/${find}/${replace}/" "./PHPCurlClass/PHP"*
    fi
}

phpunit_v6_5_shim() {
    remove_expectWarning
    replace_assertMatchesRegularExpression
    replace_assertStringContainsString
}

phpunit_v7_5_shim() {
    remove_expectWarning
    replace_assertMatchesRegularExpression
}

phpunit_v8_5_shim() {
    remove_expectWarning
    replace_assertMatchesRegularExpression
}

phpunit_v9_shim() {
    replace_assertMatchesRegularExpression
}

phpunit_v10_shim() {
    remove_expectWarning
}

set -x

composer self-update
composer install --prefer-source --no-interaction

# Use composer's phpunit and phpcs by adding composer bin directory to the path environment variable.
export PATH="${PWD}/vendor/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "CI_PHP_VERSION: ${CI_PHP_VERSION}"
echo "CI_PHP_FUTURE_RELEASE: ${CI_PHP_FUTURE_RELEASE}"
php -r "var_dump(phpversion());"
php -r "var_dump(curl_version());"

# Let test server know we should allow testing.
export PHP_CURL_CLASS_TEST_MODE_ENABLED="yes"

# Start test servers. Run servers on different ports to allow simultaneous
# requests without blocking.
server_count=7
declare -A pids
for i in $(seq 0 $(("${server_count}" - 1))); do
    port=8000
    (( port += $i ))

    php -S "127.0.0.1:${port}" server.php &> /dev/null &
    pids["${i}"]="${!}"
done

errors=()

source "check_syntax.sh"

# Determine which phpunit to use.
if [[ -f "../vendor/bin/phpunit" ]]; then
    phpunit_to_use="../vendor/bin/phpunit"
else
    phpunit_to_use="phpunit"
fi

phpunit_version="$("${phpunit_to_use}" --version | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")"
echo "phpunit_version: ${phpunit_version}"

extra_args="${@}"
if [[ "${phpunit_version}" == "6.5."* ]]; then
    phpunit_v6_5_shim
    phpunit_args=" --debug --verbose --fail-on-risky ${extra_args}"
elif [[ "${phpunit_version}" == "7.5."* ]]; then
    phpunit_v7_5_shim
    phpunit_args=" --debug --verbose --fail-on-risky ${extra_args}"
elif [[ "${phpunit_version}" == "8.5."* ]]; then
    phpunit_v8_5_shim
    phpunit_args=" --debug --verbose --fail-on-risky ${extra_args}"
elif [[ "${phpunit_version}" == "9."* ]]; then
    phpunit_v9_shim
    phpunit_args=" --debug --verbose --fail-on-risky ${extra_args}"
elif [[ "${phpunit_version}" == "10."* ]]; then
    phpunit_v10_shim
    phpunit_args=" --display-incomplete --display-skipped --display-deprecations --display-errors --display-notices --display-warnings --fail-on-risky ${extra_args}"
fi

# Run tests.
"${phpunit_to_use}" --version
"${phpunit_to_use}" \
    --configuration "phpunit.xml" \
    ${phpunit_args}
if [[ "${?}" -ne 0 ]]; then
    echo "Error: phpunit command failed"
    errors+=("phpunit command failed")
fi

source "check_coding_standards.sh"

set +x

error_count="${#errors[@]}"
if [[ "${error_count}" -ge 1 ]]; then
    echo -e "\nErrors found: ${error_count}"

    iter=0
    for value in "${errors[@]}"; do
        ((iter++))
        echo -e "\nError ${iter} of ${error_count}:"
        echo "${value}" | perl -pe 's/^(.*)$/\t\1/'
    done
fi

# Stop test servers.
for pid in "${pids[@]}"; do
  kill "${pid}" &> /dev/null &
done

if [[ "${CI_PHP_FUTURE_RELEASE}" != "true" ]]; then
    exit "${#errors[@]}"
elif [[ "${#errors[@]}" -ne 0 ]]; then
    echo "One or more tests failed, but allowed as the CI_PHP_FUTURE_RELEASE flag is on for PHP version ${CI_PHP_VERSION}."
fi
