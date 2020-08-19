#===============================================================================
# Package and Dancer2
#===============================================================================
package ytdl;
use Dancer2;


#===============================================================================
# Import Modules
#===============================================================================
use MP3::Tag;
use MP3::Info;
use Data::Dumper;
use File::Temp;
use File::Basename;
use threads;


#===============================================================================
# Public Vars
#===============================================================================
our $VERSION = '0.1';
my $tdir = File::Temp::tempdir(CLEANUP => 1);


#===============================================================================
# override term signal
#===============================================================================
$SIG{INT} = sub {
    print("Cleaning up: $tdir\n");
    system('rm', '-rf', $tdir);
    exit();
};


#===============================================================================
# Status Output
#===============================================================================
print("App Version: $VERSION\n");
print("Tempdir: $tdir\n");


#===============================================================================
# Root Page
#===============================================================================
get '/' => sub {

    # request parameters
    my $params = request->params();
    my $status = $params->{status};


    # get a list of all mp3 files
    my @files = ();
    opendir (DIR, setting('public_dir') . '/music');
    while (my $file = readdir(DIR)) {
        if ($file eq '..' || $file eq '.') { next; }
        if ($file =~ m/.mp3/) { push(@files, $file); }
    }
    closedir(DIR);


    # collect information on files
    my %files = ();
    foreach my $file (@files) {
        my $mp3t  = MP3::Tag->new(setting('public_dir')  . '/music/' . $file);
        my $mp3i  = MP3::Info->new(setting('public_dir') . '/music/' . $file);

        # get info in the mp3 file
        my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3t->autoinfo();
        my ($base, $dir, $ext) = File::Basename::fileparse($file, '\..*');
        my $length = $mp3i->time();

        # full image paths
        my $img_file_jpg  = setting('public_dir') . '/images/thumbnails/' . $base . '.jpg';
        my $img_file_webp = setting('public_dir') . '/images/thumbnails/' . $base . '.webp';

        # select the correct thumbnail type
        if (-f $img_file_jpg) {
            $files{$file}{thumb} = '/images/thumbnails/' . $base . '.jpg';
        } elsif (-f $img_file_webp) {
            $files{$file}{thumb} = '/images/thumbnails/' . $base . '.webp';
        } else {
            $files{$file}{thumb} = '/images/thumbnails/default.png';
        }

        # save file settings
        $files{$file}{length} = $length;
        $files{$file}{file}   = $file;
        $files{$file}{title}  = $title;

        # close mp3 objects
        $mp3t->close();
    }


    # render template
    template 'downloads' => {
        'title' => 'ytdl',
        'files' => \%files,
        'status' => $status,
    };

};


#===============================================================================
# add download
#===============================================================================
get '/add_download' => sub {

    my $params = request->params();
    my $status = $params->{'status'};

    template 'index' => { 'title' => 'ytdl' };
};


#===============================================================================
# Download converted file to client machine
#===============================================================================
get '/send_file' => sub {

    my $params = request->params();
    my $file   = $params->{'file'};
    my $ffile  = setting('public_dir') . '/music/' . $file;

    if (! -f $ffile) {
        redirect '/?status=File Not Found';
    } else {
        return send_file($ffile, streaming => 1, system_path => 1, filename => $file);#content_type => 'audio/mpeg, audio/x-mpeg, audio/x-mpeg-3, audio/mpeg3');
    }
};


#===============================================================================
# Play in browser
#===============================================================================
get '/play_file' => sub {

    my $params = request->params();
    my $file   = $params->{'file'};
    my $ffile  = setting('public_dir') . '/music/' . $file;
    chomp $ffile;

    my ($name, $path, $ext) = File::Basename::fileparse($ffile, '\..*');
    my $thumbnail = 'images/thumbnails/' . $name . '.jpg';

    if (! -f $ffile) {
        redirect '/?status=File Not Found';
    } else {
        template 'playback' => {
            'file' => $file,
            'thumb' => $thumbnail,
        };
    }
};


#===============================================================================
# Download the video using youtube-dl and convert it with ffmpeg and get the
# Thumbnail
#===============================================================================
post '/download_video' => sub {

    my $params = request->params();
    my $vlink  = $params->{'youtube_link'};
    my $pubdir = setting('public_dir');

    # spawn the downloading worker
    threads->create('download_convert_video', $vlink, $pubdir, $tdir);
    print('Spawning Worker Thread..' . "\n");

    # redirect back to the list
    redirect '/?status=Downloading Video.. This might take a while';

};


#===============================================================================
# async download code
#===============================================================================
sub download_convert_video {

    # vars we need
    my $vlink   = shift();
    my $pubdir  = shift();
    my $tempdir = shift();

    # fetch the thumbnail
    # get general data and thumbnail url from youtube
    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] Fetching future filename' . "\n");
    my $name = qx/youtube-dl --get-filename --restrict-filenames --output "$pubdir\/music\/\%\(title\)s\.\%\(ext\)s" $vlink/;

    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] Fetching thumbnail..' . "\n");
    my $thumbnail_url = qx/youtube-dl --get-thumbnail $vlink/;
    chomp $thumbnail_url;

    # figure out some other paths
    my ($base, $path, $ext) = File::Basename::fileparse($name, '\..*');
    my $thumbnail = $path . '../images/thumbnails/' . $base . '.jpg';
    my $mp3       = $base . '.mp3';

    # download the thumbnail to the specified location
    my $trash = qx/wget $thumbnail_url -O $thumbnail/;
    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] Done fetching thumbnail' . "\n");


    # this downloads the actual video and converts it to mp3
    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] Downloading actual video..' . "\n");
    system('youtube-dl', '--geo-bypass', '--no-call-home', '--extract-audio',
           '--audio-format', 'mp3', '--audio-quality', '0', '--embed-thumbnail',
           '--restrict-filenames', '--postprocessor-args', '-threads 4',
           '--output', $tempdir . "/%(title)s.%(ext)s", $vlink
    );
    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] Finished downloading' . "\n");

    # move the final mp3
    system('mv', '-v', $tempdir . '/' . $mp3, $pubdir . '/music/' . $mp3);

    # the worker thread is done
    print('[DOWNLOAD-WORKER(' . threads->tid() . ')] I\'m Done' . "\n");
    threads->exit();

};

true;
