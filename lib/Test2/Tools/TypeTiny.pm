package Test2::Tools::TypeTiny;

# ABSTRACT: Test2 tools for checking Type::Tiny types
# VERSION

use v5.18;
use strict;
use warnings;

use parent 'Exporter';

use List::Util v1.29 qw< uniq pairmap pairs >;
use Scalar::Util     qw< refaddr >;

use Test2::API            qw< context run_subtest >;
use Test2::Tools::Basic;
use Test2::Tools::Compare qw< is >;

use Data::Dumper;

use namespace::clean;

=encoding utf8

=head1 SYNOPSIS

    use Test2::Tools::Basic;
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

    done_testing;

=head1 DESCRIPTION

This module provides a set of tools for checking L<Type::Tiny> types.  This is similar to
L<Test::TypeTiny>, but works against the L<Test2::Suite> and has more functionality for testing
and troubleshooting coercions.

=head1 FUNCTIONS

All functions are exported by default.

=cut

our @EXPORT_OK = (qw<
    type_subtest
    should_pass_initially should_fail_initially should_pass should_fail should_coerce_into
>);
our @EXPORT = @EXPORT_OK;

=head2 Wrappers

=head3 type_subtest

    type_subtest Type, sub {
        my $type = shift;

        ...
    };

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> with the given type as the test name,
and passed as the only parameter.  Using a generic C<$type> variable makes it much easier to copy
and paste test code from other type tests without accidentally forgetting to change your custom
type within the code.

=cut

sub type_subtest ($&) {
    my ($type, $subtest) = @_;

    my $ctx  = context();
    my $pass = run_subtest(
        "Type Test: ".$type->display_name,
        $subtest,
        { buffered => 1 },
        $type,
    );
    $ctx->release;

    return $pass;
}

=head2 Testers

These functions are most useful wrapped inside of a L</type_subtest> coderef.

=head3 should_pass_initially

    should_pass_initially($type, @values);

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> that confirms the type will pass with
all of the given C<@values>, without any need for coercions.

=cut

sub should_pass_initially {
    my $ctx  = context();
    my $pass = run_subtest(
        'should pass (without coercions)',
        \&_should_pass_initially_subtest,
        { buffered => 1, inherit_trace => 1 },
        @_,
    );
    $ctx->release;

    return $pass;
}

sub _should_pass_initially_subtest {
    my ($type, @values) = @_;

    plan scalar @values;

    foreach my $value (@values) {
        my $val_dd      = _dd($value);
        my @val_explain = _constraint_type_check_debug_map($type, $value);
        ok $type->check($value), "$val_dd should pass", @val_explain;
    }
}

=head3 should_fail_initially

    should_fail_initially($type, @values);

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> that confirms the type will fail with
all of the given C<@values>, without using any coercions.

This function is included for completeness.  However, items in C<should_fail_initially> should
realistically end up in either a L</should_fail> block (if it always fails, even with coercions) or
a L</should_coerce_into> block (if it would pass after coercions).

=cut

sub should_fail_initially {
    my $ctx  = context();
    my $pass = run_subtest(
        'should fail (without coercions)',
        \&_should_fail_initially_subtest,
        { buffered => 1, inherit_trace => 1 },
        @_,
    );
    $ctx->release;

    return $pass;
}

sub _should_fail_initially_subtest {
    my ($type, @values) = @_;

    plan scalar @values;

    foreach my $value (@values) {
        my $val_dd      = _dd($value);
        my @val_explain = _constraint_type_check_debug_map($type, $value);
        ok !$type->check($value), "$val_dd should fail", @val_explain;
    }
}

=head3 should_pass

    should_pass($type, @values);

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> that confirms the type will pass with
all of the given C<@values>, including values that might need coercions.  If it initially passes,
that's okay, too.  If the type does not have a coercion and it fails the initial check, it will
stop there and fail the test.

This function is included for completeness.  However, L</should_coerce_into> is the better function
for types with known coercions, as it checks the resulting coerced values as well.

=cut

sub should_pass {
    my $ctx  = context();
    my $pass = run_subtest(
        'should pass',
        \&_should_pass_subtest,
        { buffered => 1, inherit_trace => 1 },
        @_,
    );
    $ctx->release;

    return $pass;
}

sub _should_pass_subtest {
    my ($type, @values) = @_;

    plan scalar @values;

    foreach my $value (@values) {
        my $val_dd      = _dd($value);
        my @val_explain = _constraint_type_check_debug_map($type, $value);

        if ($type->check($value)) {
            pass "$val_dd should pass (initial check)", @val_explain;
            next;
        }
        elsif (!$type->has_coercion) {
            fail "$val_dd should pass (no coercion)", @val_explain;
            next;
        }

        # try to coerce then
        my @coercion_debug = _coercion_type_check_debug_map($type, $value);
        my $new_value      = $type->coerce($value);
        my $new_dd         = _dd($new_value);
        unless (_check_coercion($value, $new_value)) {
            fail "$val_dd should pass (failed coercion)", @val_explain, @coercion_debug;
            next;
        }

        # final check
        @val_explain = _constraint_type_check_debug_map($type, $new_value);
        ok $type->check($new_value), "$val_dd should pass (coerced into $new_dd)", @val_explain, @coercion_debug;
    }
}

=head3 should_fail

    should_fail($type, @values);

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> that confirms the type will fail with
all of the given C<@values>, even when those values are ran through its coercions.

=cut

sub should_fail {
    my $ctx  = context();
    my $pass = run_subtest(
        'should fail',
        \&_should_fail_subtest,
        { buffered => 1, inherit_trace => 1 },
        @_,
    );
    $ctx->release;

    return $pass;
}

sub _should_fail_subtest {
    my ($type, @values) = @_;

    plan scalar @values;

    foreach my $value (@values) {
        my $val_dd      = _dd($value);
        my @val_explain = _constraint_type_check_debug_map($type, $value);

        if ($type->check($value)) {
            fail "$val_dd should fail (initial check)", @val_explain;
            next;
        }
        elsif (!$type->has_coercion) {
            pass "$val_dd should fail (no coercion)", @val_explain;
            next;
        }

        # try to coerce then
        my @coercion_debug = _coercion_type_check_debug_map($type, $value);
        my $new_value      = $type->coerce($value);
        my $new_dd         = _dd($new_value);
        unless (_check_coercion($value, $new_value)) {
            pass "$val_dd should fail (failed coercion)", @val_explain, @coercion_debug;
            next;
        }

        # final check
        @val_explain = _constraint_type_check_debug_map($type, $new_value);
        ok !$type->check($new_value), "$val_dd should fail (coerced into $new_dd)", @val_explain, @coercion_debug;
    }
}

=head3 should_coerce_into

    should_coerce_into($type, @orig_coerced_kv_pairs);

Creates a L<buffered subtest|Test2::Tools::Subtest/BUFFERED> that confirms the type will take the
"key" in C<@orig_coerced_kv_pairs> and coerce it into the "value" in C<@orig_coerced_kv_pairs>.
(The C<@orig_coerced_kv_pairs> parameter is essentially an ordered hash here, with support for
ref values as the "key".)

The original value should not pass initial checks, as it would not be coerced in most use cases.
These would be considered test failures.

=cut

sub should_coerce_into {
    my $ctx  = context();
    my $pass = run_subtest(
        'should coerce into',
        \&_should_coerce_into_subtest,
        { buffered => 1, inherit_trace => 1 },
        @_,
    );
    $ctx->release;

    return $pass;
}

sub _should_coerce_into_subtest {
    my ($type, @kv_pairs) = @_;

    plan int( scalar(@kv_pairs) / 2 );

    foreach my $kv (pairs @kv_pairs) {
        my ($value, $expected) = @$kv;

        my $val_dd      = _dd($value);
        my @val_explain = _constraint_type_check_debug_map($type, $value);

        if ($type->check($value)) {
            fail "$val_dd should fail (initial check)";
            next;
        }
        elsif (!$type->has_coercion) {
            fail "$val_dd should coerce (no coercion)";
            next;
        }

        # try to coerce then
        my @coercion_debug = _coercion_type_check_debug_map($type, $value);
        my $new_value      = $type->coerce($value);
        my $new_dd         = _dd($new_value);
        unless (_check_coercion($value, $new_value)) {
            fail "$val_dd should coerce", @val_explain, @coercion_debug;
            next;
        }

        # make sure it matches the expected value
        @val_explain = _constraint_type_check_debug_map($type, $new_value);
        is $new_value, $expected, "$val_dd (coerced)", @val_explain, @coercion_debug;
    }
}

# Helpers
sub _dd {
    my $dd  = Data::Dumper->new([ shift ])->Terse(1)->Indent(0)->Useqq(1)->Deparse(1)->Quotekeys(0)->Sortkeys(1)->Maxdepth(2);
    my $val = $dd->Dump;
    $val =~ s/\s+/ /gs;
    return $val;
};

sub _constraint_type_check_debug_map {
    my ($type, $value) = @_;

    my $dd = _dd($value);

    my @diag_map = ($type->display_name." constraint map:");
    if (length $dd > 30) {
        push @diag_map, "    Full value: $dd";
        $dd = '...';
    }

    my $current_check = $type;
    while ($current_check) {
        my $type_name = $current_check->display_name;
        my $check     = $current_check->check($value);

        my $check_label = $check ? 'PASSED' : 'FAILED';
        push @diag_map, sprintf("    %s->check(%s) ==> %s", $type_name, $dd, $check_label);
        local $SIG{__WARN__} = sub {};
        push @diag_map, sprintf('        is defined as: %s', $current_check->_perlcode);

        $current_check = $current_check->parent;
    };

    return @diag_map;
}

sub _coercion_type_check_debug_map {
    my ($type, $value) = @_;

    my $dd = _dd($value);

    my @diag_map = ($type->display_name." coercion map:");
    if (length $dd > 30) {
        push @diag_map, "    Full value: $dd";
        $dd = '...';
    }

    foreach my $coercion_type ($type, (pairmap { $a } @{$type->coercion->type_coercion_map}) ) {
        my $type_name = $coercion_type->display_name;
        my $check     = $coercion_type->check($value);

        my $check_label = $check ? 'PASSED' : 'FAILED';
        $check_label .= sprintf ' (coerced into %s)', _dd($type->coerce($value)) if $check && $coercion_type != $type;

        push @diag_map, sprintf("    %s->check(%s) ==> %s", $type_name, $dd, $check_label);
        last if $check;
    }

    return @diag_map;
}

sub _check_coercion {
    my ($old_value, $new_value) = @_;
    $old_value //= '';
    $new_value //= '';

    # compare memory addresses for refs instead
    ($old_value, $new_value) = map { refaddr($_) // '' } ($old_value, $new_value)
        if ref $old_value || ref $new_value
    ;

    # returns true if it was coerced
    return $old_value ne $new_value;
}

=head1 TROUBLESHOOTING

=head2 Test name output

The test names within each C<should_*> function are somewhat dynamic, depending on which stage of
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

=head3 Type Map Diagnostics

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
Based on this output, the value passed all of the lower-level C<Str> checks, because it is a string.
But, it failed the more-specific C<StrMatch> regular expression.  This will give you an idea of
which type to adjust, if necessary.

A coercion map would look like this:

    MyStringType coercion map:
        MyStringType->check("value") ==> FAILED
        FQDN->check("value") ==> FAILED
        Username->check("value") ==> FAILED
        Hostname->check("value") ==> PASSED (coerced into "value2")

The diagnostics looked at L<Type::Coercion>'s C<type_coercion_map> (and the type itself), figured
out which types were acceptable for coercion, and returned the coercion result that passed.  In
this case, none of the types passed except C<Hostname>, which was coerced into C<value2>.

Based on this, either C<Hostname> converted it to the wrong value (one that did not pass
C<MyStringType>), or one of the higher-level checks should have passed and didn't.

=cut

1;
