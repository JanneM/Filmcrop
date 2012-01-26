#!/usr/bin/ruby
require 'RMagick'
require 'optparse'
require 'pp'
ds=0
diff_fac=0.1

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

def find_minima(arr, seps, nhood)
    pstep = arr.length/(seps+1)
    diffstep = Integer(pstep*nhood)

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

# find least square minima
def find_sqr_minima(strip, frames, avgframe, nhood)
    arr = strip.intensity
    ds = strip.divs
    print "frames: ", frames, "\n"
    pstep = arr.length/(frames)
    diffstep = Integer(pstep*nhood)

    mins=Array.new(frames)

    (1..frames-2).each {|fr|

	    ps = Integer(fr*pstep)
	    pe = Integer(ps+avgframe)

	    # normalize
	    arr_start=arr.slice(ps-diffstep..ps+diffstep)
	    arr_end=arr.slice(pe-diffstep..pe+diffstep)
	    ms=arr_start.min
	    me=arr_end.min
	    arr_start.map! {|x| x-ms}
	    arr_end.map! {|x| x-me}

	    min=100000
	    finp=-1
	    (-diffstep..diffstep).each {|p|
		
		v=(arr_start[p+diffstep]**2 + 
		   arr_end[p+diffstep]**2)
		if v<min
		    min=v
		    finp=p
		end 
	    }

	    mins[fr]=[(ps+finp)*ds, (pe+finp)*ds]
    }
    mins[0]=[(mins[1][0]-avgframe*ds), (mins[1][0])]
    mins[frames-1]=[mins[frames-2][1], mins[frames-2][1]+avgframe*ds]
    mins
end

# Get a list of input files, optionally an output prefix (defaulting to
# "crop").

fheader="crop"
images=6
margin=1.0/8
dofit=true
fitsize=0
doaverage=true

optparse = OptionParser.new { |opts|

    opts.banner="Usage: filmcrop [options] file1 file2 .."
    opts.on( '-i', '--images N', Integer, 'Number of images on a strip (default 6)' ) do |f|
	images=f
	if images<2
	    puts "Need at least two images per strip\n\n", opts
	    exit
	end
    end
    opts.on( '-f', "--[no-]fit=[SIZE]", Integer, "Fit the average frame size or given frame [SIZE] to every image (default)") do |f|
	if f==nil
	    dofit = true    # default
	    doaverage=true
	elsif f==false
	    dofit = false
	else
	    dofit = true
	    doaverage=false
	    fitsize=f
	end

    end
    opts.on( '-o', '--output FILE', 'Set output file name prefix (default "crop")' ) do |f|
	fheader=f
    end

    opts.on_tail( '-h', '--help', 'Get help' ) do
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

if files.length < 1
    print "Need at least one input file.\n"
    puts optparse
    exit(0)
end
#fheader=File.basename(infile, File.extname(infile))

Img = Struct.new(:fname,	# Full size file name
		 :divs,		# scale divisor
		 :intensity,	# average value array
		 :cuts,		# found cut positions
		 :fcut,		# final frame cuts
		 :row, :col)	# size of the scaled-down image 
strips=Array.new()
files.each {|infile|

    print "Processing file: ", infile, "\n"
    instrip = Magick::Image.read(infile).first
    instrip.rotate!(-90, '<')
    ds=instrip.rows/400.0
    strip=instrip.resize(1/ds)
    instrip.destroy!

    arr=make_intense(strip, margin)
    cuts=find_minima(arr, seps, diff_fac)
    
    a=Array.new()
    strips.push(Img.new(infile, ds, arr, cuts,a, strip.rows, strip.columns))
    strip.destroy!
}

#strips.each {|s|
#    pp s.cuts
#}
#exit()

# fit to an average or given frame width 
if dofit
    print "fitting... \n"

    total=0
    mintotal=0
    nr=0
    strips.each {|s|
	if doaverage		    # find average frame size
	    (1..(seps-1)).each {|i|	    # note '1'
		total+=(s.cuts[i+1]-s.cuts[i])
		nr+=1
	    }
	else			    # use user-supplied size
	    total+=fitsize/s.divs
	    nr+=1
	end
    }
#    print "Average: ", total,"/", nr, " = ", total/nr, "\n"
    avg = Integer(total/nr)

    strips.each {|s|
	f2=find_sqr_minima(s, images, avg, diff_fac)
	s.fcut = f2
    }

# No fixed frame, so just set the cuts to each local minimum
else			
    strips.each {|s|
	(0..(seps)).each {|i|
	    f=[s.cuts[i]*s.divs, s.cuts[i+1]*s.divs]
	    s.fcut.push(f)
	}
    }
end

filenr=1
strips.each {|s|
    
    print "crop file: ", s.fname, "\n"
    instrip = Magick::Image.read(s.fname).first
    instrip.rotate!(-90, '<')
    ds=s.divs

    (0..(seps)).each {|i|
	cuts=s.fcut[i]

	outimg=instrip.crop(cuts[0],0,(cuts[1]-cuts[0]),instrip.rows,true)
	fname=format("%s.%03d.tif", fheader, filenr)
	filenr+=1
	outimg.write(fname)
	print "\t f# ", i, "\n"
	outimg.destroy!
#	print "size: ", (cuts[1]-cuts[0]),"\n"
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



