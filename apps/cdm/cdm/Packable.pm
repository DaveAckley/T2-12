package Packable;
use strict;
use fields qw(
    mPacketBytes
    );

use Exporter qw(import);

use DP qw(:all);

our @EXPORT_OK = qw(parse recognize validateAsClass);

our %EXPORT_TAGS = (
    all => \@EXPORT_OK
    );
    
our @PACKABLE_CLASSES = qw();

sub new {
    my Packable $self = shift;
    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{mPacketBytes} = undef; # Illegal value
    return $self;
}

##CLASS: Return true to declare this packet is yours
sub recognize {
    my ($class,$packet) = @_;
    return defined($packet); # Anything that exists can be a packable.
}

### CLASS METHOD
sub validateAsClass {
    my $class = shift;
    my __PACKAGE__ $pk = shift;
    return ($@ = "Undefined class", undef)    unless defined $class;
    return ($@ = "Undefined packable", undef) unless defined $pk;
    return ($@ = "Not a $class", undef)       unless $pk->isa($class);
    my $ret = $pk->validate();
    return SetError($ret)                     if defined $ret;
    return $pk;
}

### CLASS METHOD
sub assertValid {
    my ($class,$pkt) = @_;
    die "Invalid $class: $@" unless $class->validateAsClass($pkt);
    return $pkt;
}

### CLASS METHOD
sub parse {
    my ($pk) = @_;
    my $len = length($pk);
    for my $pkg (@PACKABLE_CLASSES) {
#        DPSTD("$pkg rec ");
        my $rec = $pkg->recognize($pk);
        if ($rec) {
            #DPSTD("YES $pkg");
            my $pself = $pkg->new();
            $pself->{mPacketBytes} = $pk;
            my $ret = eval {
            #DPSTD("YES1 $pkg");
                $pself->unpack();
            #DPSTD("YES2 $pkg/$pself");
                $pself;
            };
#            DPSTD("YES3 $pkg ");
            return $ret if defined $ret;
            return undef; # and $@ has error msg from eval failure
        }
    }
    $@ = "Unrecognized ".Packet::summarizeString($pk)." packet, ignored";
    return undef;
}

##VIRTUAL
sub packFormatAndVars {

    my ($self) = @_;
    return ("");
}

##VIRTUAL
sub validate {
    my __PACKAGE__ $self = shift;
    ## return undef if all is valid, else an error message
    ## subclasses do something like
    ##   my $ret = $self->SUPER::validate();
    ##   return $ret if defined $ret;
    ##   # per-class checks here
    ##   return undef;  # if all is okay
    return undef;
}

##VIRTUAL METHOD
sub prepack {
    my __PACKAGE__ $self = shift or die;
    # Base class does nothing
}
##VIRTUAL METHOD
sub postunpack {  ## RUNS BEFORE VALIDATION
    my __PACKAGE__ $self = shift or die;
    # Base class does nothing
}

sub unpack {
    my ($self) = @_;
    my ($fmt,@varrefs) = $self->packFormatAndVars();
    my @values = unpack($fmt,$self->{mPacketBytes});
#    DPSTD("valss ".join(",  ",@values));
    for (0 .. $#varrefs) {
        ${$varrefs[$_]} = $values[$_];
    }
#    DPSTD("QQUNPACK($self)");
    $self->postunpack();
    my $ret = $self->validate();
#    print Dumper(\$ret);
    die "Unpacked packet failed validation: $ret" if defined $ret;
}

sub pack {
    my __PACKAGE__ $self = shift;
    $self->prepack();
    my ($fmt,@varrefs) = $self->packFormatAndVars();
    my @values = map { $$_ } @varrefs;
#    print Dumper(\$fmt);
#    print Dumper(\@varrefs);
#    print Dumper(\@values);
    $self->{mPacketBytes} = pack($fmt, @values);
#    DPSTD("QQPACK($self)");
    my $ret = $self->validate();
    die "Packed packet failed validation: $ret" if defined $ret;
}

sub dump {
    my __PACKAGE__ $self = shift;
    my $hdl = shift;
    $hdl =  *STDOUT unless defined $hdl;
    unless (defined $self) {
        print $hdl "undef\n";
        return;
    }
    for my $key (sort keys %{$self}) {
        print $hdl "  $key = ".hexEscape($self->{$key})."\n";
    }
}

##VIRTUAL METHOD
sub summarize {
    my ($self) = @_;
    my $bytes = $self->{mPacketBytes};
    return "Unitted" unless defined($bytes);
    my $len = min(5,length($bytes));
    return hexEscape(substr($bytes,0,$len))."[$len]";
}

1;
