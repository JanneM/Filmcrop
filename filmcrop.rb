#!/usr/bin/ruby
require 'RMagick'
require 'optparse'
require 'pp'
ds=0

# create the intensity array corresponding to a given strip
# margin is how much to ignore toward the edges

def make_intense(fstrip, margin)

    rows=fstrip.rows
    cols =fstrip.columns

    acc = Array.new(cols)
    maxp = 0
    minp = 1000000

    cols.times {|x|
	pixels = fstrip.get_pixels(x,(rows*margin),1,(rows-rows*margin))
	mp=0.0
	pixels.each { |p|
	    val=p.intensity()
	    mp=val if mp < val
	}
	maxp = mp if mp > maxp
	minp = mp if mp < minp

	acc[x] = mp*1.0
    }
    acc.map! {|v| ((v)/(maxp))}
end

# Find the minima in the neighbourhood around each possible separation point

def find_minima(arr, seps)

    pstep = arr.length/(seps+1)
    diffstep = pstep/10

    mins=Array.new(seps+2)
    mins[0]=0
    mins[seps+1]=arr.length-1

    seps.times {|sep|
	pc = (sep+1)*pstep
	min=100000
	finp=-1
	((pc-diffstep)..(pc+diffstep)).each {|p|
	    if arr[p]<min
		min=arr[p]
		finp=p
	    end 
	}
	mins[sep+1] = finp
    }
    mins
end


# Get a list of input files, optionally an output prefix (defaulting to
# "crop").

fheader="crop"
images=6
margin=1.0/8

optparse = OptionParser.new { |opts|

    opts.banner="Usage: filmcrop [options] file1 file2 .."
    opts.on( '-i', '--images N', Integer, 'Number of images on a strip (default 6)' ) do |f|
	images=f
	if images<2
	    puts "Need at least two images per strip\n\n", opts
	    exit
	end
    end
    opts.on( '-o', '--output FILE', 'Set output file name prefix (default "crop")' ) do |f|
	fheader=f
    end

    opts.on( '-h', '--help', 'Get help' ) do
	puts opts
	exit
    end
}
begin optparse.parse!
rescue OptionParser::ParseError => e
    puts e, "\n", optparse
    exit 1
end

seps = images-1
files = ARGV
#fheader=File.basename(infile, File.extname(infile))

Img = Struct.new(:fname,	# Full size file name
		 :divs,		# scale divisor
		 :intensity,	# average value array
		 :cuts,		# final cut positions
		 :row, :col)	# size of the scaled-down image 
strips=Array.new()
files.each {|infile|

    instrip = Magick::Image.read(infile).first
    instrip.rotate!(-90, '<')
    ds=instrip.rows/400.0
    strip=instrip.resize(1/ds)
    arr=make_intense(strip, margin)
    cuts=find_minima(arr, seps)
    strips.push(Img.new(infile, ds, arr, cuts, strip.rows, strip.columns))
    instrip.destroy!
}

#strips.each {|s|
#    pp s.cuts
#}
#exit()

# fit to an average or set frame width 
if true
    print ""

end

filenr=1
strips.each {|s|
    
    instrip = Magick::Image.read(s.fname).first
    instrip.rotate!(-90, '<')
    ds=s.divs

    (0..(seps)).each {|i|

	outimg=instrip.crop(s.cuts[i]*ds,0,ds*(s.cuts[i+1]-s.cuts[i]),instrip.rows,true)
	fname=format("%s.%03d.tif", fheader, filenr)
	filenr+=1
	outimg.write(fname)
	print "size: ", ds*(s.cuts[i+1]-s.cuts[i]),"\n"
    }
    instrip.destroy!
}

exit()

	
pix=Array.new(1)
pix[0]=Magick::Pixel.from_color('yellow')
cols.times {|x|
    v=acc[x]*rows*0.9
    filmstrip.store_pixels(x,(rows-v),1,1,pix)}

pix[0]=Magick::Pixel.from_color('cyan')
mins.each {|p|
    filmstrip.store_pixels(p/ds,rows-1,1,1,pix)}

#filmstrip.view(0,0,cols,rows) do |view|
#    acc.each_with_index {|v,i| view[v][i]='yellow'}
#end

filmstrip.write("testout.tif")
#cols.times {|x|
#    acc

#printf("Max: %f	\t min: %f\n", maxp, minp)



