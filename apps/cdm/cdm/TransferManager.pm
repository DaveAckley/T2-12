## Module stuff
package TransferManager;
use strict;
use base 'TimeoutAble';
use fields qw(
    mDirMgr
    mMetadata
    );

use Exporter qw(import);

our @EXPORT_OK = qw();
our %EXPORT_TAGS;

## Imports
use List::Util qw(shuffle);

use DP qw(:all);
use Constants qw(DIR8_SERVER);
use T2Utils qw(:math :dirs);

## Methods
sub new {
    my TransferManager $self = shift;
    my $name = shift;
    my $cdm = shift;
    defined $name and defined $cdm or die;
    unless (ref $self) {
        $self = fields::new($self); # really a class
    }

    $self->SUPER::new("TM$name",$cdm);

    $self->{mDirMgr} = undef; # Set by subclasses
    $self->{mMetadata} = [ {}, {} ]; #  [ { cn -> { dir9 -> [dir9 cn key2 ..] } } { dir9 -> { key2 -> cn } } ]

    $self->{mCDM}->getTQ()->schedule($self);
    $self->defaultInterval(-20); # Run about every 10 seconds if nothing happening

    return $self;
}

##VIRTUAL
sub init {
    my ($self) = @_;
    DPSTD(__PACKAGE__. " init called via ".$self->getTag());
}

##VIRTUAL
sub handleAnnouncement {
    my ($self,$pkt) = @_;
    DPSTD(__PACKAGE__." handleAnnouncement not overriden for ".$pkt->summarize());
}


sub selectPair {
    my ($self,@dms) = @_;
    my $cdm = $self->getCDM() or die;
    my $hm = $cdm->{mNeighborhoodManager} or die;
    # We're picking uniformly over supplied dirmgrs, not uniformly
    # over announceable files.  This will over-emphasize the files of
    # the smaller dirmgrs, such as, we expect, pipeline/ vs common/,
    # which we suspect is A Good Thing.
    my $dm = @dms ? pickOne(@dms) : $self->{mDirMgr};

    die "Need dirmgr" unless defined $dm;
    my $mfzmgr = $dm->getRandomMFZMgr();
    my $ngbmgr = $hm->getRandomOpenNgbMgr();
    return undef unless defined($mfzmgr) && defined($ngbmgr);
    return ($mfzmgr, $ngbmgr);
}

##CLASS METHOD
sub assertMetadataRec {
    my $rec = shift;
    die "Undefined metadata rec in ${\FUNCNAME(2)}" unless defined $rec;
    die "Bad metadata rec '$rec' in ${\FUNCNAME(2)}" unless scalar(@{$rec}) >= 3;
    $rec;
}

sub _getK1MapByCN {
    my __PACKAGE__ $self = shift or die;
    my $cn = shift or die;
    return $self->getCreateMap(0,$cn);
}

sub _getK2MapByD9 {
    my __PACKAGE__ $self = shift or die;
    my $d9 = shift; die unless defined $d9;
    return $self->getCreateMap(1,$d9);
}

sub getCreateMap {
    my __PACKAGE__ $self = shift or die;
    my $idx = shift; die unless defined $idx;
    my $key = shift or die;

    my $ref1 = $self->{mMetadata}->[$idx]->{$key};
    unless (defined $ref1) {
        $ref1 = {};
        $self->{mMetadata}->[$idx]->{$key} = $ref1;
    }
    return $ref1;
}

sub getMetadata {
    my __PACKAGE__ $self = shift or die;
    my $d9 = shift;
    die unless $d9 >= 0 && $d9 <= DIR8_SERVER;
    my $cn = shift or die;
#    DPSTD("GM0 d9($d9) cn($cn)");
    my $ref1 = $self->_getK1MapByCN($cn);
#    DPSTD("GM1 '".join(", ",keys %$ref1)."'");
#    DPSTD("GM2 '".join(", ",values %$ref1)."'");
    return $ref1->{$d9};
}

sub getMetadataK2 {
    my __PACKAGE__ $self = shift or die;
    my $d9 = shift;
    die unless $d9 >= 0 && $d9 <= DIR8_SERVER;
    my $k2 = shift or die;
    my $k2map = $self->{mMetadata}->[1]->{$d9};
    return undef unless defined $k2map;
    my $cn = $k2map->{$k2};
    return undef unless defined $cn;
    return $self->getMetadata($d9,$cn);
}

sub forgetMFZMgr {
    my __PACKAGE__ $self = shift or die;
    my $mgr = shift or die;
    my $cn = $mgr->{mContentName} or die;
    DPSTD("${\FUNCNAME} $cn");
    for my $dir8 (getDir8s()) {
        my $rec = $self->getMetadata($dir8,$cn);
        next unless defined $rec;
        $self->eraseMetadata($rec);
    }
}

## PURE VIRTUAL
sub refreshServerMetadata {
    my __PACKAGE__ $self = shift or die;
    my MFZManager $mgr = shift or die;

    die "NOT OVERRIDDEN";
}

sub storeMetadata {
    my __PACKAGE__ $self = shift or die;
    my $rec = assertMetadataRec(shift);
    my $d9 = $rec->[0] or die;
    my $cn = $rec->[1] or die;
    my $k2 = $rec->[2] or die;
#    DPSTD("SM0 d9($d9) cn($cn) k2($k2)");
    my $ref1 = $self->_getK1MapByCN($cn);
#    DPSTD("SM1 '".join(", ",keys %$ref1)."'");
#    DPSTD("SM2 '".join(", ",values %$ref1)."'");

    $ref1->{$d9} = $rec;
#    DPSTD("SM3 '".join(", ",keys %$ref1)."'");
#    DPSTD("SM4 '".join(", ",values %$ref1)."'");
#    DPSTD("SM5 '".join(", ",@{$ref1->{$d9}})."'");

    my $ref2 = $self->_getK2MapByD9($d9);
    $ref2->{$k2} = $cn;
    $self->getMetadata($d9,$cn);
    DPSTD($self->getTag()." storeMetadata($d9,$cn,$k2)");
    return $rec;
}

sub eraseMetadata {
    my __PACKAGE__ $self = shift or die;
    my $rec = assertMetadataRec(shift);
    my $d9 = $rec->[0] or die;
    my $cn = $rec->[1] or die;
    my $k2 = $rec->[2] or die;
    my $cnmap = $self->_getK1MapByCN($cn);
    my $ret = $cnmap->{$d9};
    delete $cnmap->{$d9};
    my $d9map = $self->_getK2MapByD9($d9);
    delete $d9map->{$k2};
    return $ret;
}

sub createMetadataRec {
    my $d9 = shift or die;
    my $cn = shift or die;
    my $k2 = shift or die;
    my @rest = @_;
    die "Bad d9 '$d9'" unless $d9 >= 0 && $d9 <= DIR8_SERVER;
    die "Bad cn '$cn'" unless $cn =~ /[.]mfz$/;
    return [$d9, $cn, $k2, @rest];
}

sub update {
    my ($self) = @_;
    # XXX
    return 0; 
}

sub onTimeout {
    my ($self) = @_;
    DPPushPrefix($self->getTag());
    $self->update();
    DPPopPrefix(); 
}

1;
