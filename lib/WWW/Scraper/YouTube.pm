# Copyright (c) <2009> <Brandon Sandrowicz>
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.


=head1 NAME

WWW::Scraper::YouTube - YouTube Video Scraper

=head1 VERSION

Version 0.1

=head1 SYNOPSIS

Module to make it easy to scrape YouTube video pages. Scrapes URL information
for all available formats for the video.

Example:

    use WWW::Scraper::YouTube;

    my $yt = WWW::Scraper::YouTube->new();

    $yt->parse('http://www.youtube.com/watch?v=DeWsZ2b_pK4');
    my $formats = $yt->formats();
    print "Available:\n";
    for (@$formats) {
        print "\t$_: ";
        print $yt->format_description($_);
        print $yt->format_type($_);
        print "\n";
    }

    print "url: ";
    print $yt->get_url(37);
    print "\n";

=head1 FUNCTIONS

=head2 new

Creates a new WWW:Scraper::YouTube object. Takes the following optional arguments:

  ua - Supply your own LWP::UserAgent object

=head2 __create_ua

Creates the UserAgent.

=head2 parse

Parses a provided URL and internally stores all the goodies it finds.

=head2 formats

Returns an ARRAYREF, which containts the list of formats available for the
currently parsed YouTube video. Croaks if there is no page parsed.

=head2 format_description

Returns a human-readable string that describes the particular format. Returns
"Unknown" if the format doesn't exist or doesn't have a description.

=head2 format_type

Returns a string describing the format of the video. Currently just returns the
lowercase file-extension associated with the video format.

=head2 get_url

Return a download URL for the currently parsed YouTube video in the specified
format. Returns the default video if no format is specified. Returns undef if
no page is parsed.

=head2 is_page_parsed

Returns true or false based on whether or not it looks like a page has been
parsed by the current object.

=head1 LICENSE

Copyright (c) <2009> <Brandon Sandrowicz>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut

# ATRIBUTION
#   Peeked at the GreaseMonkey script here[1] to figure out what they different
#   formats were once I figured out how to extract the format codes.
#
#  [1]: http://userscripts.org/scripts/review/62634

# TODO convert JSON::XS usage over the JSON::Any

package WWW::Scraper::YouTube;

use strict;
use warnings;

use JSON::XS;
use Data::Dumper;
use LWP::UserAgent;

use Carp qw/
    croak
/;

my $formats = {
    5 => {
        desc => "Low Definition, Low Quality (FLV, Flash Video 1 (Sorenson Spark), MP3)",
        type => "flv",
        },
    6 => {
        desc => "High Quality (FLV, Flash Video 1 (Sorenson Spark), MP3)",
        type => "flv",
        },
    13 => {
        desc => "Low Quality Mobile Video (3GP, H.263, AMR)",
        type => "3gp",
        },
    17 => {
        desc => "High Quality Mobile Video (3GP, H.263, AAC)",
        type => "3gp",
        },
    18 => {
        desc => "High Quality, iPod Compatible (MP4, H.264, AAC)",
        type => "mp4",
        },
    22 => {
        desc => "High Definition, High Quality (720p) (MP4, H.264, AAC)",
        type => "mp4",
        },
    34 => {
        desc => "Low Definition, High Quality (FLV, H.264, AAC)",
        type => "flv",
        },
    35 => {
        desc => "Standard Definition, High Quality (480p) (FLV, H.264, AAC)",
        type => "flv",
        },
    37 => {
        desc => "High Definition, Super High Quality (1080p) (MP4, H.264, AAC)",
        type => "mp4",
        },
};

our $VERSION = 0.1;

sub new {
    my $class = shift;
    my $self  = {};
    my $args  = {@_};

    # process UA
    if (exists $args->{ua}) {
        $self->{ua} = $args->{ua};
    } else {
        __create_ua($self);
    }

    return bless($self,$class);
}

sub __create_ua {
    my $self = shift;
    my $ua    = LWP::UserAgent->new();
    $ua->timeout(10);
    $ua->env_proxy;
    $ua->agent("WWW::VD::YouTube/0.1");
    $self->{ua} = $ua;
    return 1;
}

sub parse {
    my $self = shift;
    my $url  = shift;

    # grab the page
    my $response = $self->{ua}->get($url);
    return undef unless $response->is_success();

    # process all of the yt.setConfig entries
    my %ytvars = ();
    my @setconfigs = ($response->content() =~ m/yt.setConfig\(\{(.*?)\n\s+\}\);/smg);
    for (@setconfigs) {
        my @entries = split /\n/, $_;
        for (@entries) {
            next if /^s*$/;
            $ytvars{$1} = $2 if $_ =~ m/^\s*'(\w+)':\s*(.*),$/;
        }
    }

    # Extract flash vars, and clean them up
    my $SWF_ARGS = decode_json $ytvars{'SWF_ARGS'};
    map { +$SWF_ARGS->{$_} =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg; } (keys %$SWF_ARGS);

    # Extract the formats
    my @formats = ();
    map { push @formats, (split m[/], $_)[0] } (split /,/, $SWF_ARGS->{fmt_map});

    # Store the relevant information
    $self->{formats}  = \@formats;
    $self->{video_id} = $SWF_ARGS->{video_id};
    $self->{token}    = $SWF_ARGS->{t};
    return 1;
}

sub formats {
    my $self = shift;
    croak "No page parsed" unless $self->is_page_parsed();
    return [ @{$self->{formats}} ];
}

sub format_description {
    my $self = shift;
    my $format_no = shift;
    return $formats->{$format_no}->{desc} if exists $formats->{$format_no}->{desc};
    return "Unknown";
}

sub format_filetype {
    my $self = shift;
    my $format_no = shift;
    return $formats->{$format_no}->{type} if exists $formats->{$format_no}->{type};
    return "Unknown";
}

sub get_url {
    my $self   = shift;
    my $format = shift;
    return undef unless $self->is_page_parsed();
    return "http://www.youtube.com/get_video?video_id=$self->{video_id}&t=$self->{token}&fmt=$format" if $format;
    return "http://www.youtube.com/get_video?video_id=$self->{video_id}&t=$self->{token}";
}

sub is_page_parsed {
    my $self = shift;
    return $self->{video_id} and $self->{token} and scalar $self->{formats};
}


1; # End of WWW::Scraper::YouTube
