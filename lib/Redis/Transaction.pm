package Redis::Transaction;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp;

use Exporter 'import';
our @EXPORT_OK = qw/multi_exec watch_multi_exec/;

sub multi_exec {
    my ($redis, $retry_count, $code) = @_;
    return watch_multi_exec($redis, [], $retry_count, sub {}, $code);
}

sub watch_multi_exec {
    my ($redis, $watch_keys, $retry_count, $before, $code) = @_;
    my $err;
    my @ret_before;
    for (1..$retry_count) {
        eval {
            $redis->watch(@$watch_keys) if @$watch_keys;
            @ret_before = $before->($redis) if $before;
        };
        if ($err = $@) {
            # clear IN-WATCHING flag, enable reconnect.
            eval {
                $redis->unwatch;
            };
            $redis->connect if $@;

            # we can retry $code because the redis has not executed $code yet.
            next;
        }

        eval {
            $redis->multi(sub {});
            $code->($redis, @ret_before);
            $redis->wait_all_responses; # force enqueue all commands
        };
        if ($err = $@) {
            # clear IN-TRANSACTION flag, enable reconnect.
            eval {
                $redis->discard;
            };
            $redis->connect if $@;

            # we can retry $code because the redis has not executed $code yet.
            next;
        }

        my $ret = eval {
            $redis->exec;
        };
        if ($err = $@) {
            if ($err =~ /\[exec\] ERR EXEC without MULTI/i) {
                # perl-redis triggers reconnect
                next;
            }

            # clear IN-TRANSACTION flag, enable reconnect.
            $redis->connect;

            # other network error.
            # watch_multi_exec cannot decide if we should reconnect
            croak $err;
        }

        # retry if someone else changed watching keys.
        next unless defined $ret;

        return (wantarray && ref $ret eq 'ARRAY') ? @$ret : $ret;
    }

    croak ($err || 'failed to retry');
}

1;
__END__

=encoding utf-8

=head1 NAME

Redis::Transaction - It's new $module

=head1 SYNOPSIS

    use Redis::Transaction;

=head1 DESCRIPTION

Redis::Transaction is ...

=head1 LICENSE

Copyright (C) Ichinose Shogo.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Ichinose Shogo E<lt>shogo82148@gmail.comE<gt>

=cut

