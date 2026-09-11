// SPDX-License-Identifier: GPL-2.0-only
#include <linux/bitops.h>
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>

#define REG_CONTROL 0x0000
#define REG_DIF_GAIN 0x0001
#define REG_REF_PWM 0x0003
#define REG_DDS_CONTROL 0x0300

struct beiis_noise {
	struct i2c_client *client;
	struct mutex lock;
	u8 generator, amplitude;
	bool output_enable, dds_enable, fm_enable;
	u16 pwm_reference;
};

static int write_reg(struct beiis_noise *n, u16 reg, u16 value)
{
	u8 data[] = { reg >> 8, reg, value >> 8, value };
	int ret = i2c_master_send(n->client, data, sizeof(data));
	return ret == sizeof(data) ? 0 : ret < 0 ? ret : -EIO;
}
static int write_control(struct beiis_noise *n)
{
	return write_reg(n, REG_CONTROL, n->generator | (n->output_enable ? BIT(3) : 0));
}
static int write_dds_control(struct beiis_noise *n)
{
	return write_reg(n, REG_DDS_CONTROL, (n->dds_enable ? BIT(0) : 0) |
			 (n->fm_enable ? BIT(1) : 0));
}

static ssize_t generator_show(struct device *d, struct device_attribute *a, char *b)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(d));
	static const char * const names[] = { "null", "prn", "dds" };
	return sysfs_emit(b, "%s\n", names[n->generator]);
}
static ssize_t generator_store(struct device *d, struct device_attribute *a, const char *b, size_t c)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(d));
	u8 v; int ret;
	if (sysfs_streq(b, "null")) v = 0;
	else if (sysfs_streq(b, "prn")) v = 1;
	else if (sysfs_streq(b, "dds")) v = 2;
	else return -EINVAL;
	mutex_lock(&n->lock); n->generator = v; ret = write_control(n); mutex_unlock(&n->lock);
	return ret ? ret : c;
}
static DEVICE_ATTR_RW(generator);

#define BOOL_ATTR(_name, _member, _write) \
static ssize_t _name##_show(struct device *d, struct device_attribute *a, char *b) \
{ struct beiis_noise *n=i2c_get_clientdata(to_i2c_client(d)); return sysfs_emit(b, "%u\n", n->_member); } \
static ssize_t _name##_store(struct device *d, struct device_attribute *a, const char *b, size_t c) \
{ struct beiis_noise *n=i2c_get_clientdata(to_i2c_client(d)); bool v; int r=kstrtobool(b,&v); if(r) return r; mutex_lock(&n->lock); n->_member=v; r=_write(n); mutex_unlock(&n->lock); return r ? r : c; } \
static DEVICE_ATTR_RW(_name)
BOOL_ATTR(output_enable, output_enable, write_control);
BOOL_ATTR(dds_enable, dds_enable, write_dds_control);
BOOL_ATTR(fm_enable, fm_enable, write_dds_control);

#define UINT_ATTR(_name, _member, _max, _reg) \
static ssize_t _name##_show(struct device *d, struct device_attribute *a, char *b) \
{ struct beiis_noise *n=i2c_get_clientdata(to_i2c_client(d)); return sysfs_emit(b, "%u\n", n->_member); } \
static ssize_t _name##_store(struct device *d, struct device_attribute *a, const char *b, size_t c) \
{ struct beiis_noise *n=i2c_get_clientdata(to_i2c_client(d)); unsigned int v; int r=kstrtouint(b,0,&v); if(r || v > _max) return -EINVAL; mutex_lock(&n->lock); r=write_reg(n,_reg,v); if(!r) n->_member=v; mutex_unlock(&n->lock); return r ? r : c; } \
static DEVICE_ATTR_RW(_name)
UINT_ATTR(amplitude, amplitude, 255, REG_DIF_GAIN);
UINT_ATTR(pwm_reference, pwm_reference, 1023, REG_REF_PWM);

static struct attribute *attrs[] = {
	&dev_attr_generator.attr, &dev_attr_output_enable.attr,
	&dev_attr_amplitude.attr, &dev_attr_pwm_reference.attr,
	&dev_attr_dds_enable.attr, &dev_attr_fm_enable.attr, NULL,
};
ATTRIBUTE_GROUPS(attrs);

static int beiis_noise_probe(struct i2c_client *client)
{
	struct beiis_noise *n = devm_kzalloc(&client->dev, sizeof(*n), GFP_KERNEL);
	if (!n) return -ENOMEM;
	n->client=client; mutex_init(&n->lock);
	n->generator=1; n->output_enable=true; n->amplitude=128;
	n->pwm_reference=512; n->dds_enable=true; n->fm_enable=true;
	i2c_set_clientdata(client,n);
	return 0;
}
static const struct of_device_id match[] = {
	{ .compatible = "be-iis,hpp-spe-noise" }, { }
};
MODULE_DEVICE_TABLE(of, match);
static struct i2c_driver driver = {
	.driver = { .name = "beiis-hpp-spe-noise", .of_match_table = match, .dev_groups = attrs_groups },
	.probe = beiis_noise_probe,
};
module_i2c_driver(driver);
MODULE_AUTHOR("Brechel Electronic");
MODULE_DESCRIPTION("BE-IIS HPP SPE NOISE control driver");
MODULE_LICENSE("GPL");
