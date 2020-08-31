## Module stuff
package Constants;
use strict;

use Exporter qw(import);

use constant CDM_PROTOCOL_VERSION_SRSLYNOW => 3;    # 202008260233 OO Refactor & cleanup
use constant CDM_PROTOCOL_VERSION_PIPELINE => 2;    # 202008140223 Pipeline overlay
use constant CDM_PROTOCOL_VERSION_ASPINNER => 1;    # Pre-version-protocol version
use constant CDM_PROTOCOL_VERSION_PREHISTORY => 0;  
use constant CDM_PROTOCOL_VERSION_UNKNOWN => -1;  

###########
use constant CDM_PROTOCOL_OUR_VERSION => CDM_PROTOCOL_VERSION_ASPINNER; #CDM_PROTOCOL_VERSION_SRSLYNOW;
###########

use constant DIR8_SERVER => 8; # Special code for us

use constant NGB_STATE_INIT => 0;
use constant NGB_STATE_CLSD => NGB_STATE_INIT+1;  # /sys/class/itc_pkt/status[dir8] == 0
use constant NGB_STATE_OPEN => NGB_STATE_CLSD+1;  # /sys/class/itc_pkt/status[dir8] > 0
use constant NGB_STATE_LIVE => NGB_STATE_OPEN+1;  # Some CDM packet received recently

use constant MFZ_STATE_INIT => 0;
use constant MFZ_STATE_NOGO => MFZ_STATE_INIT+1;  # File is known invalid
use constant MFZ_STATE_FILE => MFZ_STATE_NOGO+1;  # Has a (perhaps) stub file in filePath
use constant MFZ_STATE_CIPL => MFZ_STATE_FILE+1;  # Content is in pipeline
use constant MFZ_STATE_CCNV => MFZ_STATE_CIPL+1;  # Content is complete and verified
use constant MFZ_STATE_DEAD => MFZ_STATE_CCNV+1;  # MFZManager is dead, do not use

use constant MAX_CONTENT_NAME_LENGTH => 28;
use constant MAX_MFZ_NAME_LENGTH => MAX_CONTENT_NAME_LENGTH+4; # 4 for '.mfz'

use constant MAX_D_TYPE_DATA_LENGTH => 180;

use constant SUBDIR_COMMON => "common";
use constant SUBDIR_LOG => "log";
use constant SUBDIR_PENDING => "pending";
use constant SUBDIR_PIPELINE => "pipeline";
use constant SUBDIR_PUBKEY => "public_keys";

use constant PATH_PROG_MFZRUN => "/home/t2/MFM/bin/mfzrun";

use constant CDM_DELETEDS_MFZ => "cdm-deleteds.mfz";
use constant CDMD_T2_12_MFZ =>   "cdmd-T2-12.mfz";
use constant CDMD_MFM_MFZ =>     "cdmd-MFM.mfz";

use constant HOOK_TYPE_LOAD => "LOAD";
use constant HOOK_TYPE_RELEASE => "RELEASE";

use constant ANNOUNCE_PACK_DATA_FORMAT =>
    ""  # 0
        ."CCa"        #   0 +   3 =   3 hdr
        ."C"          #   3 +   1 =   4 announce version
        ."N"          #   4 +   4 =   8 inner timestamp
        ."N"          #   8 +   4 =  12 inner length
        ."n"          #  12 +   2 =  14 regnum
        ."a8"         #  14 +   8 =  22 inner checksum
        ."a28"        #  22 +  28 =  50 content name
        #  50 total length for data
    ;

use constant ANNOUNCE_PACK_PACKET_FORMAT =>
    "" # 0
        ."a50"        #   0 +  50 =  50 data
        ."a128"       #  50 + 128 = 178 RSA sig of bytes 0..49
    ;

use constant ANNOUNCE_UNPACK_OUTPUT_FORMAT =>
    "" # 0
    . "a178"
    . "a*"
    ;

use constant ANNOUNCE_PACKET_LENGTH => 178;

my @subdirs = qw(
    SUBDIR_COMMON
    SUBDIR_LOG
    SUBDIR_PENDING
    SUBDIR_PIPELINE
    SUBDIR_PUBKEY
    );

my @mfzfiles = qw(
    CDM_DELETEDS_MFZ
    CDMD_T2_12_MFZ
    CDMD_MFM_MFZ
    );

my @constants = qw(
    CDM_PROTOCOL_VERSION_SRSLYNOW
    CDM_PROTOCOL_VERSION_PIPELINE 
    CDM_PROTOCOL_VERSION_ASPINNER
    CDM_PROTOCOL_VERSION_PREHISTORY
    CDM_PROTOCOL_VERSION_UNKNOWN
    CDM_PROTOCOL_OUR_VERSION

    DIR8_SERVER

    NGB_STATE_INIT
    NGB_STATE_CLSD
    NGB_STATE_OPEN
    NGB_STATE_LIVE

    MFZ_STATE_INIT
    MFZ_STATE_NOGO
    MFZ_STATE_FILE
    MFZ_STATE_CIPL
    MFZ_STATE_CCNV
    MFZ_STATE_DEAD

    MAX_CONTENT_NAME_LENGTH
    MAX_MFZ_NAME_LENGTH
    MAX_D_TYPE_DATA_LENGTH

    ANNOUNCE_PACK_DATA_FORMAT
    ANNOUNCE_PACK_PACKET_FORMAT
    ANNOUNCE_UNPACK_OUTPUT_FORMAT
    ANNOUNCE_PACKET_LENGTH

    HOOK_TYPE_LOAD
    HOOK_TYPE_RELEASE

    );

my @paths = qw(
    PATH_PROG_MFZRUN
    );

our @EXPORT_OK = (@constants, @subdirs, @mfzfiles, @paths);
our %EXPORT_TAGS =
    (
     constants => \@constants,
     subdirs => \@subdirs,
     mfzfiles => \@mfzfiles,
     paths => \@paths,
     all => \@EXPORT_OK
    );

1;
