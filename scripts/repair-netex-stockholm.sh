#!/usr/bin/env bash
# Requires Bash, Info-ZIP zip/unzip, Perl and XML::Twig; no Python is used.
# Usage:
#   scripts/repair-netex-stockholm.sh [input.zip] [output.zip]
#
# args default to local-test/input/netex/Napcorex.zip and local-test/input/netex/Napcorex-patched-stockholm.zip

set -euo pipefail

usage() {
    printf 'Usage: %s [input.zip [output.zip]]\n' "${0##*/}"
    printf 'Defaults: local-test/input/netex/Napcorex.zip local-test/input/netex/Napcorex-patched-stockholm.zip\n'
    printf 'Restored platforms use parent-station coordinates, not surveyed positions.\n'
}

fail() {
    printf 'Feed repair failed: %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi
[[ $# -le 2 ]] || { usage >&2; exit 2; }
for tool in unzip zip perl realpath mktemp cp mv rm rmdir cat sort uniq grep; do
    command -v "$tool" >/dev/null || fail "Required command is missing: $tool"
done
perl -MXML::Twig -e 1 || fail 'Install the Perl XML::Twig module (Debian/Ubuntu: libxml-twig-perl).'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
default_source="$script_directory/local-test/input/netex/Napcorex.zip"
default_destination="$script_directory/local-test/input/netex/Napcorex-patched-stockholm.zip"
source_file=$(realpath -e -- "${1:-$default_source}") || fail 'Source archive does not exist.'
destination=$(realpath -m -- "${2:-$default_destination}") || fail 'Cannot resolve output path.'
[[ -f $source_file ]] || fail 'Source must be a regular ZIP file.'
[[ $source_file != "$destination" && ! $source_file -ef $destination ]] ||
    fail 'Output must differ from the original feed.'
[[ ! -d $destination ]] || fail 'Output is a directory.'
output_directory=${destination%/*}
[[ -d $output_directory ]] || fail 'Output directory does not exist.'

work_directory=$(mktemp -d "$output_directory/.repair-netex.XXXXXXXX")
cleanup() {
    rm -f -- "$work_directory/_stops.xml" "$work_directory/_shared_data.xml" \
        "$work_directory/archive.zip" "$work_directory/entries" \
        "$work_directory/duplicates" "$work_directory/stats"
    rmdir -- "$work_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "Feed repair failed at line %s.\n" "$LINENO" >&2' ERR

unzip -Z1 "$source_file" > "$work_directory/entries"
sort "$work_directory/entries" | uniq -d > "$work_directory/duplicates"
[[ ! -s $work_directory/duplicates ]] || fail 'Duplicate ZIP entry names.'
for entry in _stops.xml _shared_data.xml; do
    grep -Fxq -- "$entry" "$work_directory/entries" || fail "Missing ZIP entry: $entry"
    unzip -p "$source_file" "$entry" > "$work_directory/$entry"
done

# Use an XML parser rather than line-based substitutions: NeTEx elements can
# span lines, use namespace prefixes and contain escaped text.
perl - "$work_directory" <<'PERL'
use strict;
use warnings;
use XML::Twig;

my ($directory) = @ARGV;
my $namespace = 'http://www.netex.org.uk/netex';

sub is_element {
    my ($element, $name) = @_;
    return $element->local_name eq $name
        && ($element->namespace // '') eq $namespace;
}

sub elements {
    my ($root, $name) = @_;
    return grep { is_element($_, $name) } $root->descendants;
}

sub child {
    my ($element, $name) = @_;
    return unless defined $element;
    return (grep { is_element($_, $name) } $element->children)[0];
}

sub required_attribute {
    my ($element, $name) = @_;
    my $value = $element->att($name);
    die "Missing $name on " . $element->tag . "\n" unless defined $value;
    return $value;
}

sub unique_index {
    my ($root, $name) = @_;
    my %index;
    for my $element (elements($root, $name)) {
        my $id = required_attribute($element, 'id');
        die "Duplicate $name: $id\n" if exists $index{$id};
        $index{$id} = $element;
    }
    return \%index;
}

sub platform_ids {
    my ($stop_point) = @_;
    $stop_point =~ /\ASE:001:ScheduledStopPoint:(9022[0-9]{12})\z/
        or die "Unsupported Stockholm scheduled stop identifier: $stop_point\n";
    my $code = $1;
    return ("SE:001:Quay:$code",
        'FTG:StopPlace:9021' . substr($code, 4, 9) . '000',
        substr($code, -3));
}

sub qualified_name {
    my ($parent, $name) = @_;
    my $qualified = $parent->tag;
    $qualified =~ s/[^:]+\z/$name/;
    return $qualified;
}

my $stops = XML::Twig->new(no_xxe => 1);
my $shared = XML::Twig->new(no_xxe => 1);
$stops->parsefile("$directory/_stops.xml");
$shared->parsefile("$directory/_shared_data.xml");
my $places = unique_index($stops->root, 'StopPlace');
my $quays = unique_index($stops->root, 'Quay');
my $scheduled = unique_index($shared->root, 'ScheduledStopPoint');
my @assignments = elements($shared->root, 'PassengerStopAssignment');
die "Expected Stockholm StopPlaces, Quays and PassengerStopAssignments\n"
    unless keys(%$places) && keys(%$quays) && @assignments;

for my $place (values %$places) {
    my $container = child($place, 'quays');
    next unless defined $container;
    for my $quay (grep { is_element($_, 'Quay') } $container->children) {
        my $stop_point = required_attribute($quay, 'id');
        $stop_point =~ s/:Quay:/:ScheduledStopPoint:/;
        my (undef, $parent_id) = platform_ids($stop_point);
        die "Platform does not match its station: " . $quay->att('id') . "\n"
            unless $parent_id eq $place->att('id');
    }
}

my %stats = (
    assignments => scalar @assignments,
    original_quays => scalar keys %$quays,
    rewritten_quay_refs => 0,
    restored_quays_at_station_centroids => 0,
);
for my $assignment (@assignments) {
    my $stop_ref = child($assignment, 'ScheduledStopPointRef');
    my $quay_ref = child($assignment, 'QuayRef');
    die "Incomplete PassengerStopAssignment: " . $assignment->att('id') . "\n"
        unless defined $stop_ref && defined $quay_ref;
    my $stop_id = required_attribute($stop_ref, 'ref');
    die "ScheduledStopPoint is absent: $stop_id\n" unless exists $scheduled->{$stop_id};
    my ($quay_id, $parent_id, $platform) = platform_ids($stop_id);
    die "Parent station is absent for $stop_id: $parent_id\n"
        unless exists $places->{$parent_id};
    unless (exists $quays->{$quay_id}) {
        my $place = $places->{$parent_id};
        my $centroid = child($place, 'Centroid');
        my $location = child($centroid, 'Location');
        die "Parent station has no coordinates: $parent_id\n"
            unless defined child($location, 'Latitude')
                && defined child($location, 'Longitude');
        my $container = child($place, 'quays');
        unless (defined $container) {
            $container = XML::Twig::Elt->new(qualified_name($place, 'quays'));
            $container->paste(last_child => $place);
        }
        my $quay = XML::Twig::Elt->new(qualified_name($container, 'Quay'),
            { version => '1', id => $quay_id });
        $quay->paste(last_child => $container);
        XML::Twig::Elt->new(qualified_name($quay, 'PrivateCode'), 0 + $platform)
            ->paste(last_child => $quay);
        $centroid->copy->paste(last_child => $quay);
        $quays->{$quay_id} = $quay;
        ++$stats{restored_quays_at_station_centroids};
    }
    if (required_attribute($quay_ref, 'ref') ne $quay_id) {
        $quay_ref->set_att(ref => $quay_id);
        $quay_ref->del_att('version');
        ++$stats{rewritten_quay_refs};
    }
}
for my $ref (elements($shared->root, 'QuayRef')) {
    my $id = required_attribute($ref, 'ref');
    die "Unresolved quay reference after repair: $id\n" unless exists $quays->{$id};
}
$stats{output_quays} = scalar keys %$quays;
$stops->set_encoding('UTF-8');
$shared->set_encoding('UTF-8');
$stops->print_to_file("$directory/_stops.xml");
$shared->print_to_file("$directory/_shared_data.xml");
open my $report, '>', "$directory/stats" or die "Cannot write repair statistics: $!\n";
for my $name (qw(assignments original_quays rewritten_quay_refs
    restored_quays_at_station_centroids output_quays)) {
    print {$report} "  $name: $stats{$name}\n" or die "Cannot write statistics: $!\n";
}
if ($stats{restored_quays_at_station_centroids}) {
    print {$report} "WARNING: Restored platform coordinates are station centroids, not surveyed positions.\n"
        or die "Cannot write coordinate warning: $!\n";
}
close $report or die "Cannot close repair statistics: $!\n";
PERL

# Updating a copy preserves all other entries and the original archive comment.
cp -- "$source_file" "$work_directory/archive.zip"
(
    cd -- "$work_directory"
    zip -q archive.zip _stops.xml _shared_data.xml
)
unzip -tq "$work_directory/archive.zip" >/dev/null
mv -f -- "$work_directory/archive.zip" "$destination"
printf 'Repaired feed: %s\n' "$destination"
cat -- "$work_directory/stats"
