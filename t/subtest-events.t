#!/usr/bin/perl

use lib 't/lib';
use StrTest;

use Test2::API            qw< intercept >;
use Test2::Tools::Basic;
use Test2::Tools::Compare qw< is like >;
use Test2::Tools::Subtest qw< subtest_buffered >;

use List::Util   qw< first >;
use Scalar::Util qw< blessed >;

###################################################################################################

my $events = intercept { StrTest::string_test(1); };

# Analysis of finished test
is(
    $events->state,
    {
        count      => 3,
        failed     => 2,
        is_passing => 0,

        plan         => 3,
        follows_plan => 1,

        bailed_out  => undef,
        skip_reason => undef,
    },
    'Event summary is correct',
);

is(
    [
        map { s/Test2::Event:://; $_ }
        map { blessed $_ }
        $events->event_list
    ],
    [qw< Subtest Diag Subtest Subtest Diag Plan >],
    'Order of events are correct',
);

my @subtest_events = grep { blessed $_ eq 'Test2::Event::Subtest' } $events->event_list;

is( $subtest_events[0]->pass, 0, 'StrMatch subtest failed');
is( $subtest_events[1]->pass, 1, 'First Enum subtest passed');
is( $subtest_events[2]->pass, 0, 'Second Enum subtest failed');

subtest_buffered 'Failed StrMatch subtest' => sub {
    my @strmatch_subtest_events = grep { blessed $_ eq 'Test2::Event::Subtest' } @{ $subtest_events[0]->subevents };

    is(
        [ map { $_->effective_pass } @strmatch_subtest_events ],
        [qw< 1 1 1 1 1 0 0 >],
        'StrMatch pass/fail order is correct',
    );

    my $failed_strmatch_subtest = first { !$_->effective_pass } @strmatch_subtest_events;

    my $strmatch_diags = join("\n",
        map  { $_->message }
        grep { blessed $_ eq 'Test2::Event::Diag' }
        @{ $failed_strmatch_subtest->subevents }
    );

    like $strmatch_diags, qr<at t/str-test.t line 44>,             'Failed test includes line numbers';
    like $strmatch_diags, qr<StrMatch\[.+\] constraint map:>,      'Failed test includes constraint map diag';
    like $strmatch_diags, qr<is defined as:>,                      'Constraint map diag includes type definitions';
    like $strmatch_diags, qr{\QStr->check("xyz km") ==> PASSED\E}, 'Constraint map diag passed Str check';
};

subtest_buffered 'Failed Enum subtest' => sub {
    my @enum_subtest_events =
        map  { @{ $_->subevents } }
        grep { blessed $_ eq 'Test2::Event::Subtest' }
        @{ $subtest_events[2]->subevents }
    ;

    is(
        [
            map  { $_->isa('Test2::Event::Fail') ? 0 : $_->effective_pass }
            grep { $_->isa('Test2::Event::Ok') || $_->isa('Test2::Event::Fail') }
            @enum_subtest_events
        ],
        [qw< 0 0 1 1 0 0 0 >],
        'Enum->should_coerce_into pass/fail order is correct',
    );

    my $enum_diags = join("\n",
        map   { $_->message }
        grep  { blessed $_ eq 'Test2::Event::Diag' }
        @enum_subtest_events
    );

    like $enum_diags, qr<at t/str-test.t line 88>,             'Failed test includes line numbers';
    like $enum_diags, qr<Enum\[.+\] constraint map:>,          'Failed test includes constraint map diag';
    like $enum_diags, qr<is defined as:>,                      'Constraint map diag includes type definitions';
    like $enum_diags, qr{\QStr->check("XYZ") ==> PASSED\E},    'Constraint map diag passed Str check';
    like $enum_diags, qr<Enum\[.+\] coercion map:>,            'Failed test includes coercion map diag';
    like $enum_diags, qr{\QStr->check("XYZ") ==> PASSED (coerced into "XYZ")\E}, 'Coercion map diag passed Str check';
};

done_testing;
