

#import "ViewController.h"

#import "mo_audio.h" //stuff that helps set up low-level audio
#import "FFTHelper.h"


#define SAMPLE_RATE 44100  //22050 //44100
#define FRAMESIZE  512
#define NUMCHANNELS 2
#define USE_VOICE 0
//#define MIN_SOUND_MAGNITUDE 0.00000000001f
#define MIN_SOUND_MAGNITUDE 0.00000001f

#define kOutputBus 0
#define kInputBus 1



/// Nyquist Maximum Frequency
const Float32 NyquistMaxFreq = SAMPLE_RATE/2.0;

/// caculates HZ value for specified index from a FFT bins vector
Float32 frequencyHerzValue(long frequencyIndex, long fftVectorSize, Float32 nyquistFrequency ) {
    return ((Float32)frequencyIndex/(Float32)fftVectorSize) * nyquistFrequency;
}


// The Main FFT Helper
FFTHelperRef *fftConverter = NULL;



//Accumulator Buffer=====================

const UInt32 accumulatorDataLenght = 16384;  //16384; //32768; 65536; 131072;
UInt32 accumulatorFillIndex = 0;
Float32 *dataAccumulator = nil;
static void initializeAccumulator() {
    dataAccumulator = (Float32*) malloc(sizeof(Float32)*accumulatorDataLenght);
    accumulatorFillIndex = 0;
}
static void destroyAccumulator() {
    if (dataAccumulator!=NULL) {
        free(dataAccumulator);
        dataAccumulator = NULL;
    }
    accumulatorFillIndex = 0;
}

static BOOL accumulateFrames(Float32 *frames, UInt32 lenght) { //returned YES if full, NO otherwise.
    //    float zero = 0.0;
    //    vDSP_vsmul(frames, 1, &zero, frames, 1, lenght);
    
    if (accumulatorFillIndex>=accumulatorDataLenght) { return YES; } else {
        memmove(dataAccumulator+accumulatorFillIndex, frames, sizeof(Float32)*lenght);
        accumulatorFillIndex = accumulatorFillIndex+lenght;
        if (accumulatorFillIndex>=accumulatorDataLenght) { return YES; }
    }
    return NO;
}

static void emptyAccumulator() {
    accumulatorFillIndex = 0;
    memset(dataAccumulator, 0, sizeof(Float32)*accumulatorDataLenght);
}
//=======================================


//==========================Window Buffer
const UInt32 windowLength = accumulatorDataLenght;
Float32 *windowBuffer= NULL;
//=======================================



/// max value from vector with value index (using Accelerate Framework)
static Float32 vectorMaxValueACC32_index(Float32 *vector, unsigned long size, long step, unsigned long *outIndex) {
    Float32 maxVal;
    vDSP_maxvi(vector, step, &maxVal, outIndex, size);
    return maxVal;
}




///returns HZ of the strongest frequency.
static Float32 strongestFrequencyHZ(Float32 *buffer, FFTHelperRef *fftHelper, UInt32 frameSize, Float32 *freqValue) {
    
    
    //the actual FFT happens here
    //****************************************************************************
    Float32 *fftData = computeFFT(fftHelper, buffer, frameSize);
    //****************************************************************************
    
    
    fftData[0] = 0.0;
    unsigned long length = frameSize/2.0;
    Float32 max = 0;
    unsigned long maxIndex = 0;
    max = vectorMaxValueACC32_index(fftData, length, 1, &maxIndex);
    if (freqValue!=NULL) { *freqValue = max; }
    Float32 HZ = frequencyHerzValue(maxIndex, length, NyquistMaxFreq);
    
    return HZ;
}



__weak UILabel *labelToUpdate = nil;
__weak UILabel *labelKeyName = nil;

Float32* delta;

int octave(Float32 nFreq, Float32 kFreq)
{
    return (int)((nFreq/kFreq)/2);
}

Float32 between(Float32 nFreq, Float32 kFreq)
{
    Float32 octave = roundf((nFreq/kFreq)/2);
    Float32 normFreq = nFreq/octave;
//    Float32 delta = MAX(normFreq,kFreq) - MIN(normFreq, kFreq);
    Float32 delta = MAX(roundf(octave),octave) - MIN(roundf(octave), octave);

    
    //NSLog(@"nfreq=%0.3f octave=%0.3f normfreq=%0.3f kfreq =%0.3f delta=%0.3f", nFreq, octave,normFreq, kFreq,delta);
   
    return delta;
}

Float32* baseFreq;

#define B1 61.7354f
#define A1_2 58.2705f
#define A1 55.0f
#define G1_2 51.9131f
#define G1 48.9994f
#define F1_2 46.2493f
#define F1 43.6535f
#define E1 41.2034f
#define D1_2 38.8909f
#define D1 36.7081f
#define C1_2 34.6478f
#define C1 32.7032f

float lowest = 10;
bool isLowest(Float32 n)
{
    if (n < lowest) {
        lowest = n;
        return true;
    }
    return false;
}

#define fequal(a,b) (fabs((a) - (b)) < 0.001f)
#define fequal_freq(a,b) (fabs((a) - (b)) < 1.0f)

NSString* getKey(Float32 n)
{
//    for (int i=0; i<12; ++i) {
//        delta[i] = between(n, baseFreq[i]);
//        isLowest( delta[i] );
//    }
//    int oct = 0;
//    int bestIndex = -1;
//    for (int i=0; i<12; ++i) {
//        oct = octave(n, baseFreq[i]);
//        NSLog(@"nfreq=%0.3f octave=%i", n, oct);
//        if(oct % 2 == 0 && lowest == delta[i])
//        {
//            bestIndex = i;
//        }
//    }
    
    int oct = 20;
    int bestIndex = -1;
 // n = 783.3f; // g
    for (int i=0; i<12; ++i) {
        for (int j=1; j<10; ++j) {
            if (fabs((baseFreq[i]*powf(2, j)) - (n)) < (1.0f*powf(2, j))) {
                bestIndex = i;
                oct = j+1;
            }
//            int curroct = (int)roundf((n / baseFreq[i])/2);
//            if( curroct < oct && curroct % 2 == 0)
//            {
//                oct = curroct;
//                bestIndex = i;
//            }
        }
    }
    
    NSLog(@"bestindex %i basefreq %f equal %i", bestIndex, baseFreq[bestIndex], fequal(baseFreq[bestIndex], B1));
    
    if (bestIndex == -1) {
        return @"---";
    } else if (fequal(baseFreq[bestIndex], B1)) {
        return [NSString stringWithFormat:@"B%i", oct];
    } else if(fequal(baseFreq[bestIndex], A1_2)){
        return [NSString stringWithFormat:@"A♯%i/B♭%i", oct, oct];
    } else if(fequal(baseFreq[bestIndex], A1)){
        return [NSString stringWithFormat:@"A%i", oct];
    } else if(fequal(baseFreq[bestIndex], G1_2)){
        return [NSString stringWithFormat:@"G♯%i/A♭%i", oct, oct];
    } else if(fequal(baseFreq[bestIndex], G1)){
        return [NSString stringWithFormat:@"G%i", oct];
    } else if(fequal(baseFreq[bestIndex], F1_2)){
        return [NSString stringWithFormat:@"F♯%i/G♭%i", oct, oct];
    } else if(fequal(baseFreq[bestIndex], F1)){
        return [NSString stringWithFormat:@"F%i", oct];
    } else if(fequal(baseFreq[bestIndex], E1)){
        return [NSString stringWithFormat:@"E%i", oct];
    } else if(fequal(baseFreq[bestIndex], D1_2)){
        return [NSString stringWithFormat:@"D♯%i/E♭%i", oct, oct];
    } else if(fequal(baseFreq[bestIndex], D1)){
        return [NSString stringWithFormat:@"D%i", oct];
    } else if(fequal(baseFreq[bestIndex], C1_2)){
        return [NSString stringWithFormat:@"C♯%i/D♭%i", oct, oct];
    } else if(fequal(baseFreq[bestIndex], C1)){
        return [NSString stringWithFormat:@"C%i", oct];
    }
    return @"---";
}

#pragma mark MAIN CALLBACK
void AudioCallback( Float32 * buffer, UInt32 frameSize, void * userData )
{
    
    
    //take only data from 1 channel
    Float32 zero = 0.0;
    vDSP_vsadd(buffer, 2, &zero, buffer, 1, frameSize*NUMCHANNELS);
    
    
    
    if (accumulateFrames(buffer, frameSize)==YES) { //if full
        
        //windowing the time domain data before FFT (using Blackman Window)
        if (windowBuffer==NULL) { windowBuffer = (Float32*) malloc(sizeof(Float32)*windowLength); }
        vDSP_blkman_window(windowBuffer, windowLength, 0);
        vDSP_vmul(dataAccumulator, 1, windowBuffer, 1, dataAccumulator, 1, accumulatorDataLenght);
        //=========================================
        
        
        Float32 maxHZValue = 0.0f;
        Float32 maxHZ = strongestFrequencyHZ(dataAccumulator, fftConverter, accumulatorDataLenght, &maxHZValue);
        //NSLog(@" max Mag = %0.11f", maxHZValue);
       // NSLog(@" max HZ = %0.3f", maxHZ);
        
        if(maxHZValue >= MIN_SOUND_MAGNITUDE){
            NSString *keyName = getKey(maxHZ);
            dispatch_async(dispatch_get_main_queue(), ^{ //update UI only on main thread
                labelToUpdate.text = [NSString stringWithFormat:@"%0.1f HZ",maxHZ];
                labelKeyName.text = keyName;
            });

        }
        
        
        emptyAccumulator(); //empty the accumulator when finished
    }
    memset(buffer, 0, sizeof(Float32)*frameSize*NUMCHANNELS);
}




void initBuffer()
{
    baseFreq = (Float32*) malloc(sizeof(Float32)*12);
    baseFreq[0] = B1;
    baseFreq[1] = A1_2;
    baseFreq[2] = A1;
    baseFreq[3] = G1_2;
    baseFreq[4] = G1;
    baseFreq[5] = F1_2;
    baseFreq[6] = F1;
    baseFreq[7] = E1;
    baseFreq[8] = D1_2;
    baseFreq[9] = D1;
    baseFreq[10] = C1_2;
    baseFreq[11] = C1;
    
    delta = (Float32*) malloc(sizeof(Float32)*12);
}







@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    labelToUpdate = HZValueLabel;
    labelKeyName = KeyNameLabel;
    
    //initialize stuff
    fftConverter = FFTHelperCreate(accumulatorDataLenght);
    initializeAccumulator();
    initBuffer();
    [self initMomuAudio];

}

-(void) initMomuAudio {
    bool result = false;
    result = MoAudio::init( SAMPLE_RATE, FRAMESIZE, NUMCHANNELS, USE_VOICE);
    if (!result) { NSLog(@" MoAudio init ERROR"); }
    result = MoAudio::start( AudioCallback, NULL );
    if (!result) { NSLog(@" MoAudio start ERROR"); }
}




- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


-(void) dealloc {
    destroyAccumulator();
    FFTHelperRelease(fftConverter);
}

@end
