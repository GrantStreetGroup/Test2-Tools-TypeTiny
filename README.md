# NAME

Test2::Tools::TypeTiny - Test2 tools for checking Type::Tiny types

# VERSION

version v0.90.0

# SYNOPSIS

    use Test2::Tools::TypeTiny;
    use MyTypes qw< FullyQualifiedDomainName >;

    type_subtest FullyQualifiedDomainName, sub {
        my $type = shift;

        should_pass_initially(
            $type,
            qw<
                www.example.com
                example.com
                www123.prod.some.domain.example.com
                llanfairpwllgwyngllgogerychwyrndrobwllllantysiliogogogoch.co.uk
            >,
        );
        should_fail_initially(
            $type,
            qw< www ftp001 ftp001-prod3 .com domains.t x.c >,
        );
        should_fail(
            $type,
            qw< www ftp001 .com domains.t x.c prod|ask|me -prod3.example.com >,
        );
        should_coerce_into(
            $type,
            qw<
                ftp001-prod3                ftp001-prod3.ourdomain.com
                prod-ask-me                 prod-ask-me.ourdomain.com
                nonprod3-foobar-me          nonprod3-foobar-me.ourdomain.com
            >,
        );
    };

# DESCRIPTION

This module provides a set of tools for checking [Type::Tiny](https://metacpan.org/pod/Type%3A%3ATiny) types.  This is similar to
[Test::TypeTiny](https://metacpan.org/pod/Test%3A%3ATypeTiny), but works against the [Test2::Suite](https://metacpan.org/pod/Test2%3A%3ASuite) and has more functionality for testing
and troubleshooting coercions.

It also comes with a standard set of imports, to make your `use` list more compact.

# EXPORTS

This module uses [Import::Base](https://metacpan.org/pod/Import%3A%3ABase) to load pragmas.

## Defaults

This module loads in a bunch of pragmas and includes a default set of exports.  A single call to
`use Test2::Tools::TypeTiny` is roughly equivalent to the following:

    # Pragmas
    use v5.18;
    use strict;
    use warnings;
    use utf8;
    use open      qw< :std :utf8 >;
    use filetest  'access';
    use charnames qw< :full :short >;

    # Exports
    use Test2::Tools::Basic;
    use Test2::Tools::TypeTiny qw< Default >;  # all documented functions

You can use the special bundle of `NoExports` to start off fresh.  (Pragmas will still be loaded
in.)

    use Test2::Tools::TypeTiny qw< NoExports type_subtest >;
    use Test2::Tools::Basic    qw< plan done_testing >;

# FUNCTIONS

## Wrappers

### type\_subtest

    type_subtest Type, sub {
        my $type = shift;

        ...
    };

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) with the given type as the test name,
and passed as the only parameter.  Using a generic `$type` variable makes it much easier to copy
and paste test code from other type tests without accidentally forgetting to change your custom
type within the code.

## Testers

These functions are most useful wrapped inside of a ["type\_subtest"](#type_subtest) coderef.

### should\_pass\_initially

    should_pass_initially($type, @values);

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) that confirms the type will pass with
all of the given `@values`, without any need for coercions.

### should\_fail\_initially

    should_fail_initially($type, @values);

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) that confirms the type will fail with
all of the given `@values`, without using any coercions.

### should\_pass

    should_pass($type, @values);

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) that confirms the type will pass with
all of the given `@values`, including values that might need coercions.  If it initially passes,
that's okay, too.  If the type does not have a coercion and it fails the initial check, it will
stop there and fail the test.

This function is included for completeness.  However, ["should\_coerce\_into"](#should_coerce_into) is the better function
for types with known coercions, as it checks the resulting coerced values as well.

### should\_fail

    should_fail($type, @values);

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) that confirms the type will fail with
all of the given `@values`, even when those values are ran through its coercions.

### should\_coerce\_into

    should_coerce_into($type, @orig_coerced_kv_pairs);

Creates a [buffered subtest](https://metacpan.org/pod/Test2%3A%3ATools%3A%3ASubtest#BUFFERED) that confirms the type will take the
"key" in `@orig_coerced_kv_pairs` and coerce it into the "value" in `@orig_coerced_kv_pairs`.
(The `@orig_coerced_kv_pairs` parameter is essentially an ordered hash here, with support for
ref values as the "key".)

The original value should not pass initial checks, as it would not be coerced in most use cases.
These would be considered test failures.

# TROUBLESHOOTING

## Test name output

The test names within each `should_*` function are somewhat dynamic, depending on which stage of
the test it failed at.  Most of the time, this is self-explanatory, but double negatives may make
the output a tad logic-twisting:

    not ok 1 - ...

    # should_*_initially
    "val" should pass                        # simple should_pass_initially failure
    "val" should fail                        # simple should_fail_initially failure

    # should_*
    "val" should fail (initial check)        # should_fail didn't initially fail
    "val" should pass (no coercion)          # should_pass initally failed, and didn't have a coercion to use
    "val" should pass (failed coercion)      # should_pass failed both the check and coercion
    "val" should fail (coerced into "val2")  # should_fail still successfully coerced into a good value
    "val" should pass (coerced into "val2")  # should_pass coerced into a bad value

    # should_coerce_into has similar errors as above

### Type Map Diagnostics

Because types can be twisty mazes of inherited parents or multiple coercion maps, any failures will
produce a verbose set of diagnostics.  These come in two flavors: constraint maps and coercion maps,
depending on where in the process the test failed.

For example, a constraint map could look like:

    # (some definition output truncated)

    MyStringType constraint map:
        MyStringType->check("value") ==> FAILED
            is defined as: do { package Type::Tiny; ... ) }
        StrMatch["(?^ux:...)"]->check("value") ==> FAILED
            is defined as: do { package Type::Tiny; !ref($_) and !!( $_ =~ $Types::Standard::StrMatch::expressions{"..."} ) }
        StrMatch->check("value") ==> PASSED
            is defined as: do { package Type::Tiny; defined($_) and do { ref(\$_) eq 'SCALAR' or ref(\(my $val = $_)) eq 'SCALAR' } }
        Str->check("value") ==> PASSED
            is defined as: do { package Type::Tiny; defined($_) and do { ref(\$_) eq 'SCALAR' or ref(\(my $val = $_)) eq 'SCALAR' } }
        Value->check("value") ==> PASSED
            is defined as: (defined($_) and not ref($_))
        Defined->check("value") ==> PASSED
            is defined as: (defined($_))
        Item->check("value") ==> PASSED
            is defined as: (!!1)
        Any->check("value") ==> PASSED
            is defined as: (!!1)

The diagnostics checked the final value with each individual parent check (including itself).
Based on this output, the value passed all of the lower-level `Str` checks, because it is a string.
But, it failed the more-specific `StrMatch` regular expression.  This will give you an idea of
which type to adjust, if necessary.

A coercion map would look like this:

    MyStringType coercion map:
        MyStringType->check("value") ==> FAILED
        FQDN->check("value") ==> FAILED
        Username->check("value") ==> FAILED
        Hostname->check("value") ==> PASSED (coerced into "value2")

The diagnostics looked at [Type::Coercion](https://metacpan.org/pod/Type%3A%3ACoercion)'s `type_coercion_map` (and the type itself), figured
out which types were acceptable for coercion, and returned the coercion result that passed.  In
this case, none of the types passed except `Hostname`, which was coerced into `value2`.

Based on this, either `Hostname` converted it to the wrong value (one that did not pass
`MyStringType`), or one of the higher-level checks should have passed and didn't.

# AUTHOR

Grant Street Group <developers@grantstreet.com>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2024 by Grant Street Group.

This is free software, licensed under:

    The Artistic License 2.0 (GPL Compatible)
