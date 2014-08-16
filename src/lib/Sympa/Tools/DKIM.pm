# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014 GIP RENATER
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sympa::Tools::DKIM;

use strict;
use warnings;
use English qw(-no_match_vars);

use Conf;
use Log;

sub get_dkim_parameters {
    Log::do_log('debug2', '(%s)', @_);
    my $that = shift;

    my ($robot_id, $list);
    if (ref $that eq 'Sympa::List') {
        $robot_id = $that->{'domain'};
        $list     = $that;
    } elsif ($that and $that ne '*') {
        $robot_id = $that;
    } else {
        $robot_id = '*';
    }

    my $data;
    my $keyfile;
    if ($list) {
        # fetch dkim parameter in list context
        $data->{'d'} = $list->{'admin'}{'dkim_parameters'}{'signer_domain'};
        if ($list->{'admin'}{'dkim_parameters'}{'signer_identity'}) {
            $data->{'i'} =
                $list->{'admin'}{'dkim_parameters'}{'signer_identity'};
        } else {
            # RFC 4871 (page 21)
            $data->{'i'} = $list->get_list_address('owner');    # -request
        }
        $data->{'selector'} = $list->{'admin'}{'dkim_parameters'}{'selector'};
        $keyfile = $list->{'admin'}{'dkim_parameters'}{'private_key_path'};
    } else {
        # in robot context
        $data->{'d'} = Conf::get_robot_conf($robot_id, 'dkim_signer_domain');
        $data->{'i'} =
            Conf::get_robot_conf($robot_id, 'dkim_signer_identity');
        $data->{'selector'} =
            Conf::get_robot_conf($robot_id, 'dkim_selector');
        $keyfile = Conf::get_robot_conf($robot_id, 'dkim_private_key_path');
    }

    return undef
        unless defined $data->{'d'}
            and defined $data->{'selector'}
            and defined $keyfile;

    my $fh;
    unless (open $fh, '<', $keyfile) {
        Log::do_log('err', 'Could not read dkim private key %s: %m',
            $keyfile);
        return undef;
    }
    $data->{'private_key'} = do { local $RS; <$fh> };
    close $fh;

    return $data;
}

# input a msg as string, output the dkim status
sub verifier {
    my $msg_as_string = shift;
    my $dkim;

    Log::do_log('debug', 'DKIM verifier');
    unless (eval "require Mail::DKIM::Verifier") {
        Log::do_log('err',
            "Failed to load Mail::DKIM::verifier perl module, ignoring DKIM signature"
        );
        return undef;
    }

    unless ($dkim = Mail::DKIM::Verifier->new()) {
        Log::do_log('err', 'Could not create Mail::DKIM::Verifier');
        return undef;
    }

    my $temporary_file = $Conf::Conf{'tmpdir'} . "/dkim." . $PID;
    if (!open(MSGDUMP, "> $temporary_file")) {
        Log::do_log('err', 'Can\'t store message in file %s',
            $temporary_file);
        return undef;
    }
    print MSGDUMP $msg_as_string;

    unless (close(MSGDUMP)) {
        Log::do_log('err', 'Unable to dump message in temporary file %s',
            $temporary_file);
        return undef;
    }

    unless (open(MSGDUMP, "$temporary_file")) {
        Log::do_log('err', 'Can\'t read message in file %s', $temporary_file);
        return undef;
    }

    # this documented method is pretty but dont validate signatures, why ?
    # $dkim->load(\*MSGDUMP);
    while (<MSGDUMP>) {
        chomp;
        s/\015$//;
        $dkim->PRINT("$_\015\012");
    }

    $dkim->CLOSE;
    close(MSGDUMP);
    unlink($temporary_file);

    foreach my $signature ($dkim->signatures) {
        return 1 if ($signature->result_detail eq "pass");
    }
    return undef;
}

1;