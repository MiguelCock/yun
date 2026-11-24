module yun::input;

const double REPEAT_DELAY    = 0.30;
const double REPEAT_INTERVAL = 0.08;

enum WordClass : int
{
	SPACE,
	WORD,
	PUNCT,
}

fn WordClass word_class(char c)
{
	int b = (int)c & 0xFF;
	if (b <= 32) return WordClass.SPACE;
	if ((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_')
	{
		return WordClass.WORD;
	}
	if (b >= 0x80) return WordClass.WORD;
	return WordClass.PUNCT;
}

struct RepeatState
{
	int dir;
	double next;
}

fn void RepeatState.start(&self, int dir, double now)
{
	self.dir = dir;
	self.next = now + REPEAT_DELAY;
}

fn void RepeatState.reset(&self)
{
	self.dir = 0;
	self.next = 0.0;
}

fn int RepeatState.tick(&self, int held_dir, double now)
{
	if (held_dir == 0)
	{
		self.dir = 0;
		return 0;
	}
	if (self.dir != held_dir)
	{
		self.dir = held_dir;
		self.next = now + REPEAT_DELAY;
		return 0;
	}
	if (now < self.next) return 0;
	self.next = now + REPEAT_INTERVAL;
	return held_dir;
}