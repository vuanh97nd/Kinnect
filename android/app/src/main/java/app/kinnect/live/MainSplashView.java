package app.kinnect.live;

import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.graphics.Outline;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.Interpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Launch splash view builder and animator extracted from MainActivity. */
final class MainSplashView {
  private MainSplashView() {}

  static AnimatorSet show(Activity activity, AnimatorSet previous, int bgColor, int accentColor, LinearLayout column, TextView nameLabel) {
    if (previous != null) {
      previous.cancel();
    }
    float density = activity.getResources().getDisplayMetrics().density;
    int logoPx = Math.round(96f * density);
    final float logoRadius = 22f * density;
    int gapPx = Math.round(18f * density);
    int ringPx = Math.round(22f * density);
    int ringStroke = Math.max(2, Math.round(2.5f * density));
    int ringsWidth = Math.round(96f * density);
    int ringsHeight = Math.round(36f * density);
    float spread = 16f * density;
    float overlap = 5f * density;

    FrameLayout s = new FrameLayout(activity);
    s.setClipChildren(false);
    s.setClipToPadding(false);
    s.setBackgroundColor(bgColor);

    column.setGravity(Gravity.CENTER_HORIZONTAL);
    column.setClipChildren(false);
    column.setClipToPadding(false);

    ImageView logo = new ImageView(activity);
    logo.setImageResource(activity.getResources().getIdentifier("kinnect_logo", "drawable", activity.getPackageName()));
    logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
    logo.setElevation(Math.round(12f * density));
    logo.setOutlineProvider(new ViewOutlineProvider() {
      @Override
      public void getOutline(View view, Outline outline) {
        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), logoRadius);
      }
    });
    LinearLayout.LayoutParams logoLp = new LinearLayout.LayoutParams(logoPx, logoPx);
    logoLp.gravity = Gravity.CENTER_HORIZONTAL;
    column.addView(logo, logoLp);

    nameLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f);
    nameLabel.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    nameLabel.setIncludeFontPadding(false);
    nameLabel.setSingleLine(true);
    nameLabel.setGravity(Gravity.CENTER);
    LinearLayout.LayoutParams nameLp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
    nameLp.gravity = Gravity.CENTER_HORIZONTAL;
    nameLp.topMargin = gapPx;
    column.addView(nameLabel, nameLp);

    FrameLayout rings = new FrameLayout(activity);
    rings.setClipChildren(false);
    rings.setClipToPadding(false);
    View[] ringViews = new View[2];
    int[] ringColors = { accentColor, 0xffed45aa };
    boolean animate = ValueAnimator.areAnimatorsEnabled();
    for (int i = 0; i < 2; i++) {
      View ring = new View(activity);
      GradientDrawable outline = new GradientDrawable();
      outline.setShape(GradientDrawable.OVAL);
      outline.setColor(0x00000000);
      outline.setStroke(ringStroke, ringColors[i]);
      ring.setBackground(outline);
      float initialOffset = animate ? (i == 0 ? -spread : spread) : (i == 0 ? -overlap : overlap);
      ring.setTranslationX(initialOffset);
      FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(ringPx, ringPx, Gravity.CENTER);
      rings.addView(ring, rp);
      ringViews[i] = ring;
    }
    LinearLayout.LayoutParams space = new LinearLayout.LayoutParams(ringsWidth, ringsHeight);
    space.gravity = Gravity.CENTER_HORIZONTAL;
    space.topMargin = gapPx;
    column.addView(rings, space);

    s.addView(column, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
    activity.setContentView(s);
    activity.getWindow().setStatusBarColor(bgColor);
    activity.getWindow().setNavigationBarColor(bgColor);

    if (!animate) {
      return null;
    }
    Interpolator ease = new AccelerateDecelerateInterpolator();
    ObjectAnimator pulseX = ObjectAnimator.ofFloat(logo, View.SCALE_X, 1f, 1.05f);
    ObjectAnimator pulseY = ObjectAnimator.ofFloat(logo, View.SCALE_Y, 1f, 1.05f);
    ObjectAnimator move0 = ObjectAnimator.ofFloat(ringViews[0], View.TRANSLATION_X, -spread, -overlap);
    ObjectAnimator move1 = ObjectAnimator.ofFloat(ringViews[1], View.TRANSLATION_X, spread, overlap);
    for (ObjectAnimator anim : new ObjectAnimator[] { pulseX, pulseY, move0, move1 }) {
      anim.setDuration(600);
      anim.setInterpolator(ease);
      anim.setRepeatCount(ValueAnimator.INFINITE);
      anim.setRepeatMode(ValueAnimator.REVERSE);
    }
    AnimatorSet set = new AnimatorSet();
    set.playTogether(pulseX, pulseY, move0, move1);
    set.start();
    return set;
  }
}
