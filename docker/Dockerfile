FROM ubuntu:latest

EXPOSE 3001:5000

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y less wget build-essential apt-utils git
RUN wget https://yt-dl.org/downloads/latest/youtube-dl -O /usr/local/bin/youtube-dl
RUN chmod a+rx /usr/local/bin/youtube-dl
RUN apt-get install -y ffmpeg
RUN cpan -i MP3::Tag
RUN cpan -i MP3::Info
RUN cpan -i File::Temp
RUN cpan -i File::Basename
RUN git clone https://github.com/CC3301/ytdl
RUN echo "DONE"

ENTRYPOINT cd ytdl/ && plackup -E production bin/app.psgi
