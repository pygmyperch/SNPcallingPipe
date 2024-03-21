package samdedup;

use strict;
use warnings;
use File::Basename;

my $LEVEL = 1;

sub dedup {
    my @arg = @_;
    my ($inf, $outf, $nc, $ncp);

    foreach my $ar (@arg) {
        if ($ar =~ /^-i/) { $inf = (split(/ /, $ar))[1]; }
        elsif ($ar =~ /^-o/) { $outf = (split(/ /, $ar))[1]; }
        elsif ($ar =~ /^-lnc/) { $nc = (split(/ /, $ar))[1]; }
        elsif ($ar =~ /^-snc/) { $ncp = (split(/ /, $ar))[1]; }
    }

    unless (defined $inf) {
        print "\nThis script will convert from sam to bam, sort by name, fixmates, sort by coordinates and mark duplicates using samtools in parallel. Requires your sam files after mapping (sample01.sam), all saved in one folder.\n\nUsages: samtoolsdup.pl\n\t-i <path to input folder>\n\nOptional:\n\t-o <path to output folder, default samout>\n\t-nc <number of cores or samples to use in parallel, default 4>\n\t-ncp <number of cores per sample, default 1>\n\n";
        exit;
    }

    $outf //= "./samout"; # Set default value if not defined
    my $tmpdir = "$outf/tmp";
    my $names = "$outf/name";
    my $fix = "$outf/fix";
    my $coor = "$outf/cdnt";
    my $ddp = "$outf/dedup";

    foreach my $ofn ($tmpdir, $names, $fix, $coor, $ddp) {
        mkdir $ofn unless -d $ofn;
        chmod 0775, $ofn;
    }

    $nc //= 4;
    $ncp //= 1;

    my $ext = `ls $inf/ | tail -n 1 | awk -F '.' '{print \$NF}'`;
    chomp $ext;
    my @names = `ls $inf/*.$ext`;
    chomp @names; # Remove newline character from each element

    # Extract just the filename without the .sam extension from each full path
    my @nms = map { basename($_, ".$ext") } @names;

    my $cmd;
    if ($ext eq "sam") {
        $cmd = "parallel -j $nc samtools view -bS $inf/{1}.$ext '|' " .
               "samtools sort -n -@ $ncp -o $names/{1}_namesort.bam - ::: @nms";
    } elsif ($ext eq "bam") {
        $cmd = "parallel -j $nc samtools sort -n -@ $ncp -o $names/{1}_namesort.bam $inf/{1}.$ext ::: @nms";
    }

    my $cmd2 = "parallel -j $nc samtools fixmate -m $names/{1}_namesort.bam $fix/{1}_fixmate.bam ::: @nms";
    my $cmd3 = "parallel -j $nc samtools sort -@ $ncp -o $coor/{1}_positionsort.bam $fix/{1}_fixmate.bam ::: @nms";
    my $cmd4 = "parallel -j $nc samtools markdup -r -s $coor/{1}_positionsort.bam $ddp/{1}_markdup.bam > $tmpdir/{1}_log ::: @nms";

    print "$cmd\n\n$cmd2\n\n$cmd3\n\n$cmd4\n\n";

    # Execute the commands
    system($cmd) == 0 or die "Failed to execute: $cmd";
    system($cmd2) == 0 or die "Failed to execute: $cmd2";
    system($cmd3) == 0 or die "Failed to execute: $cmd3";
    system($cmd4) == 0 or die "Failed to execute: $cmd4";
}

# Helper subroutine to create directory if it does not exist
sub make_dir {
    my $dir = shift;
    unless (-d $dir) {
        mkdir $dir or die "Failed to create $dir: $!";
        chmod 0775, $dir;
    }
}

1;
